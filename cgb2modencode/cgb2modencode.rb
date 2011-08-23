#!/usr/bin/ruby

$:.unshift(File.dirname(__FILE__))

require 'mediawiki_bot'
require 'modencode_template'
require 'atlassianwiki_bot'
require 'dbfields_bot'
require 'tempfile'
require 'yaml'

DEFAULT_INI_FILE="cgb-wiki-bot.yml"
DEFAULT_CACHE_FILE="cgb.cache"
DEFAULT_CACHE_AGE=86400

ini_file = ARGV[0] || File.join(File.dirname(__FILE__), DEFAULT_INI_FILE)
@config = File.open(ini_file) { |f| YAML.load(f) }

# Clean up the cache file if it's too old
cache_file = @config["cache_file"] || File.join(File.dirname(__FILE__), DEFAULT_CACHE_FILE)
if (File.exists?(cache_file)) then
  cache_age = Time.now - File.mtime(cache_file)
  max_cache_age = @config["max_cache_age"] || DEFAULT_CACHE_AGE
  File.unlink(cache_file) if cache_age >= max_cache_age
end

cgbb = nil
if !File.exists?(cache_file) then
  # Open CGB connection
  cgbb = AtlassianwikiBot.new(@config["cgb_wiki"]["uri"])

  # Get the list of antibodies
  ab_page = cgbb.get_page_text(@config["cgb_wiki"]["page"])

  # Parse the antibody listing
  abs = ab_page.split(/\n/).map { |ab| ab.sub(/^\s*\|\s*/, '').split(/\s*\|\s+/) }
  header_row = abs.find_index { |ab| ab[0] =~ /RNA ID/ }
  header = abs[header_row]
  abs.slice!(0..header_row)

  header.map! { |h| h.gsub(/\*/, '') }
  abs.map! { |ab| h = Hash[*header.zip(ab).flatten] }

  abs.map! { |ab|
    rna_id = ab["RNA ID"].match(/\*\}(\d+)\*/)[1] # ID looks like: "{anchor:170}{*}170*"
    # Old version -- no longer works
    #rna_id = ab["RNA ID"].match(/\*(\d+)\*/)[1]
    bs_id = ab["Biological sample ID"].match(/\d+/)[0]
    cell_type = ab["sample"].gsub(/^\W+|\|.*/, '').gsub(/\\\+/, '+')
    qc_pages = ab["RNA QC"].split(/\s*,\s*/).map { |qc| qc.gsub(/^\[|\]$/, '').gsub(/\\\+/, '+').split(/\|/) } if ab["RNA QC"]
    prep_page = ab["preparation method"].gsub(/^\[|\]$/, '').gsub(/\\\+/, '+').split(/\|/) if ab["preparation method"]
    ab[:qc_pages] ||= []

    { :rna_id => rna_id, :bs_id => bs_id, :cell_type => cell_type, :qc_pages => qc_pages, :prep_page => prep_page }
  }
  File.open(cache_file, "w") { |f| Marshal.dump(abs, f) }
else
  abs = File.open(cache_file) { |f| Marshal.restore(f) }
end


# Open modENCODE wiki connection
me = MediawikiBot.new(@config["modencode_wiki"]["uri"])
# Open modENCODE DBFields connection
dbf = DbfieldsBot.new(@config["dbfields"]["uri"])

# Verify wiki synchronization
abs.each { |ab|
  puts "Checking sample #{ab[:rna_id]} for up-to-dateness."

  # Build template page from existing page, if any
  # Also fetch DBFields form content, if any
  title = "Celniker/RNA:#{ab[:rna_id]}"
  puts "  Page is #{title}"
  begin
    me_text = me.get_page_text(title)
    me_page = ModencodeTemplate.new(me_text)
    begin
      me_form = dbf.get_data(title)
    rescue DbfieldsBot::NoFormDataException
      me_form = {}
    end
  rescue MediawikiBot::PageNotFoundException, ModencodeTemplate::BadPageContentException => e
    puts "  #{e.message}"
    me_page = ModencodeTemplate.new
    me_form = {}
  end

  # Create a ModencodeTemplate from the remote antibody info
  cgb_page = ModencodeTemplate.new
  cgb_page.scraped_data = [ 
    "RNA ID: #{ab[:rna_id]}",
    "Biosample: #{ab[:bs_id]}",
    "Cell type: #{ab[:cell_type]}"
  ].join("\n")

  # Generate protocol links
  display_base = URI.parse(@config["cgb_wiki"]["uri"])
  display_base.user = display_base.password = nil
  cgb_page.protocols = ([ ab[:prep_page] ] + ab[:qc_pages].to_a).compact.map { |p|
    m = @config["mappings"][p[0].to_s.gsub(/^\s*|\s*$/, '')]
    # If there's a mapping for it, use that
    # Otherwise, if there was a URL on the original page, use that
    # Otherwise, it's a link to the CGB wiki from the original page.
    page = m.nil? ? p[0] : m["page"]
    desc = m.nil? ? (p[1] =~ /:\/\// ? p[1] : "#{display_base.merge(p[1].to_s.gsub(/ /, '+'))}") : m["desc"]
    if m.nil? then
      puts "  Using #{page}|#{desc} since there's no mapping for #{p[0]}"
    end
    # Two different link formats: the first is for external links, the second is internal links
    m.nil? ? "[#{page} #{desc}]" : "[[#{page}|#{desc}]]"
  }.map { |p| p.sub(/^/, '*') }.join("\n")

  # Generate QC image links
  # This is a quick check to see if the QC pages match
  # We just check the link text so we don't have to go get the filename from CGB (which is extra page loads)
  cgb_qc_images = ab[:qc_pages].to_a.map { |p| p[1] }.sort
  me_qc_images = me_page.qcdata.split(/\n+/).map { |q| p = q.gsub(/^\*\[\[|\]\]$/, '').split(/\|/)[1] }.sort unless me_page.qcdata.nil?
  # If the link text is correct, then just go ahead and assume the image files are correct
  cgb_page.qcdata = me_page.qcdata if (me_qc_images == cgb_qc_images && @config["lazy_qc_checks"])

  # Check the templates against each other
  if ( cgb_page.scraped_data == me_page.scraped_data && cgb_page.protocols == me_page.protocols &&
      cgb_page.qcdata == me_page.qcdata) then
    puts "  Wiki text matches."
  else
    puts "  Updating wiki text."
    # Update wiki text
    # Do we need to fully populate QC data, or is it okay?
    if cgb_page.qcdata != me_page.qcdata || me_page.qcdata.nil?
      # Fetch/upload QC images from CGB
      puts "    Fetching QC data."
      cgbb ||= AtlassianwikiBot.new(@config["cgb_wiki"]["uri"]) # Login if not already logged in
      cgb_page.qcdata = ab[:qc_pages].to_a.map { |p|
        begin
          html = cgbb.get_page(p[1].gsub(/\s/, '+')).body
          wiki = cgbb.get_page_text_for_content(html)
          m = wiki.match(/!([^!]*)!/)
        rescue
          puts "    Failed to fetch page for #{p[1]}; thought there would be QC data here."
        end
        img_name = m[1] unless m.nil?
        u = html.match(/src="([^"]*#{Regexp.escape(img_name.gsub(/\s/, '+'))}[^"]*)"/) unless img_name.nil?
        src = u[1] unless u.nil?
        if src then
          res_file = nil
          Tempfile.open("dgrc_image") { |f|
            # Fetch remote image
            src = cgbb.get_page(src)
            f.puts src.body

            # Upload image
            f.rewind
            res_file = me.upload_image(img_name, f)
          }
          raise RuntimeException.new("Unable to upload file; nil response object from wiki") if res_file.nil?
          "[[Image:#{res_file}|#{p[1]}]]"
        else
          puts "    No QC image found on page #{p[1]}"
          "[[Image:No_QC_image|#{p[1]}]]"
        end
      }.join("\n")
      me_page.qcdata = cgb_page.qcdata
    end
    me_page.scraped_data = cgb_page.scraped_data
    me_page.protocols = cgb_page.protocols

    # Post new text
    res = me.update_page(title, me_page.content)
  end

  cgb_form = { "RNA ID" => ab[:rna_id], "Official Name" => ab[:cell_type], "Biosample #" => ab[:bs_id] }
  if (me_form == cgb_form) then
    puts "  DBFields content matches."
  else
    puts "  Updating DBFields content."
    # Update form content
    res = dbf.update(me, title, cgb_form)
  end
}

