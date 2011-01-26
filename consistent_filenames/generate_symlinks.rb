#!/usr/bin/ruby
require 'pp'
require 'find'
require 'fileutils'

class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
end

class Renamer
    TYPES = {
      :regulome => [ "binding site", "chromatin" ],
      :regulome_repfactors => [ "replication factors" ],
      :chromatin => [ "chromatin modification" ],
      :chromatin_ori => [ "origins of replication" ],
      :chromatin_reptiming => [ "replication timing" ],
      :transcriptome => [ "gene model", "RNA profiling", "transcription" ],
      :transcriptome_cnv => [ "copy number variation" ],
      :raw_sequence => [ "raw sequences" ],
      :other => [ "(metadata only)", "signal data" ]
    }
  def initialize(csv_path, data_path, output_path)
    @csv_path = csv_path
    @data_path = data_path
    @output_path = output_path
    raise Exception.new("Invalid arguments.") if (@csv_path.nil? || @data_path.nil? || @output_path.nil?)
    raise Exception.new("Can't read file: #{@csv_path}") unless (File.file?(@csv_path) && File.readable?(@csv_path))
    raise Exception.new("Not a folder: #{@data_path}") unless File.directory?(@data_path)
    raise Exception.new("Not a folder: #{@output_path}") unless File.directory?(@output_path)
    raise Exception.new("Can't write to: #{@output_path}") unless File.writable?(@output_path)
    raise Exception.new("Not empty: #{@output_path}") unless Dir.glob(File.join(@output_path, "*"), File::FNM_DOTMATCH).reject { |f| File.basename(f) == "." || File.basename(f) == ".." }.size == 0
  end

  def run
    all_freeze_data = Renamer.get_freeze_data(@csv_path)[0]
    all_freeze_data.sort { |a, b| a[:submission_id].to_i <=> b[:submission_id].to_i }.each do |freeze_data|
      listing = get_listing(freeze_data[:submission_id])

      organism = freeze_data["Organism"].sub(/^(.).*? (...).*$/, '\1\2').upcase
      assay = freeze_data["Assay"].upcase.gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, "")

      category = TYPES.find { |k, v| freeze_data["Data Type"].split(/,\s*/).find { |data_type| v.include?(data_type) } }
      category = (category.nil? ? :other : category[0])
      category = :unreleased if (freeze_data["Data Type"].blank? || freeze_data["Data Type"] == "N/A")

      strain = (freeze_data["Strain"] =~ /N\/A/i) ? nil : "STRAIN_#{freeze_data["Strain"]}"
      stage = freeze_data[:stages].map { |stage| (stage =~ /N\/A/i) ? nil : stage }.compact.join("_and_")
      condition = freeze_data[:stages].map { |stage| (stage =~ /N\/A/i) ? nil : stage }.compact.join("__") if stage.size > 0
      stage = stage.blank? ? nil : "STAGE_#{stage}" 
      tissue = (freeze_data["Tissue"] =~ /N\/A/i) ? nil : "TISSUE_#{freeze_data["Tissue"]}"
      condition = freeze_data["Tissue"] unless freeze_data["Tissue"].sub('N/A', '').blank?
      cell_line = (freeze_data["Cell Line"] =~ /N\/A/i) ? nil : "CELL_LINE_#{freeze_data["Cell Line"]}"
      condition = freeze_data["Cell Line"] unless freeze_data["Cell Line"].sub('N/A', '').blank?
      target = (freeze_data["Experimental Factor"] =~ /N\/A/i) ? nil : freeze_data["Experimental Factor"]
      target = target.split(/;/).map { |d| d.split(/=/) }.find_all { |d| d[0] == "Target" }.map { |k, v| v }.join("_and_") unless target.nil?
      target = target.blank? ? nil : "TARGET_#{target}"
      sid = "SID_#{freeze_data[:submission_id]}"
      antibodies = freeze_data[:antibodies].reject { |ab| ab == "N/A" }

      condition = "Computational_Results" if freeze_data["Assay"] == "Computational annotation"

#      puts "No condition for #{freeze_data.pretty_inspect}" if condition.nil?
      condition = "Other_Condition" if condition.nil?

      condition = condition.gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, "")
      dirname = case category
                when :transcriptome then
                  File.join("Transcriptome", condition)
                when :transcriptome_cnv then
                  File.join("Transcriptome", "Copy_Number_Variation", condition)
                when :regulome then
                  File.join("Regulome", antibodies.map { |x| x = x.split(/=>/)[0]; x.gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, "") }.join("__"), condition)
                when :regulome_repfactors then
                  File.join("Regulome", antibodies.map { |x| x = x.split(/=>/)[0]; x.gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, "") }.join("__"), condition)
                when :chromatin
                  if antibodies.size == 0 && freeze_data[:compounds].find { |c| c =~ /SaltConcentration/ } then
                    target = "TREATMENT_" + freeze_data[:compounds].find { |c| c =~ /SaltConcentration/ }.split(/=/)[1]
                  end
                  File.join("Chromatin", antibodies.map { |x| x = x.split(/=>/)[0]; x.gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, "") }.join("__"), condition)
                when :chromatin_ori
                  File.join("Chromatin", "Origins_of_Replication", condition)
                when :chromatin_reptiming
                  File.join("Chromatin", "Replication_Timing", condition)
                when :raw_sequence
                  File.join("Raw_Sequence", freeze_data["Assay"].gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, ""))
                when :unreleased
                  File.join("Unreleased", freeze_data[:submission_id].to_s)
                when :other
                  "Other"
                end

      category = category.to_s.upcase
      
      listing.each do |file|
        (filename, path) = file

        orig_filename = ""
        orig_filename = File.dirname(filename).gsub("/", "_") if File.dirname(filename) != "."
        orig_filename += "_" if orig_filename.length > 0
        orig_filename += File.basename(filename)

        file_parts = [ organism, category, strain, cell_line, tissue, stage, target, sid ].compact.map { |x| x.gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, "") } + [ orig_filename ]
        file[1] = File.join(@output_path, dirname, file_parts.join("_"))
      end

      listing.each { |src, dest|
        puts "#{src} -> #{dest}"
        FileUtils.mkdir_p(File.dirname(dest)) unless File.directory?(File.dirname(dest))
        File.symlink(src, dest)
      }
    end
  end
  def apply_pretty_naming
  end
  def get_listing(submission_id)
    listing = Array.new
    current_directory = File.join(@data_path, submission_id, "extracted")
    unless File.directory?(current_directory)
      $stderr.puts "No such folder #{current_directory}"
      return listing 
    end
    Find.find(current_directory) do |path|
      next if File.basename(path) == File.basename(current_directory)
      unless File.directory?(path) then
        subdir = File.dirname(path)[current_directory.length..-1] || ""
        listing.push [ path, File.join(subdir, File.basename(path)).sub(/^\/*/, '') ]
      end
    end
    return listing
  end
  def self.get_freeze_data(filename)
    data = Array.new
    headers = []
    File.open(filename) { |f|
      headers = f.gets.chomp.split(/\t/)
      while ((line = f.gets) != nil) do
        fields = line.chomp.split(/\t/).map { |field| (field == "" ? "N/A" : field) }
        d = Hash.new; headers.each_index { |n| d[headers[n]] = (fields[n].nil? ? nil : fields[n].gsub(/^"|"$/, '')) }
        data.push d
      end
    }
    self.extract_and_attach_factor_info(data)
    return [ data, headers ]
  end
  def self.extract_and_attach_factor_info(freeze_data)
    # We group some fields together and put them into symbol-keyed entries in the @freeze_data hash
    # because older generated spreadsheets had these fields separate
    # This is the mapping of human-readable column name to grouped field, which gets used when
    # defining a matrix view
    @freeze_header_translation = {
      "Antibody" => :antibodies,
      "Platform" => :array_platforms,
      "Compound" => :compounds,
      "RNAi Target" => :rnai_targets,
      "Stage/Treatment" => :stages,
    }

    if freeze_data.find { |project_info| project_info["Experimental Factor"] } then
      freeze_data.each { |project_info| 
        factors = project_info["Experimental Factor"].split(/[;,]\s*/).flatten.uniq.inject(Hash.new { |h, k| h[k] = Array.new }) { |h, factor| 
          (k,v) = factor.split(/=/)
          h[k].push v
          h
        }
        treatments = project_info["Treatment"].split(/[;,]\s*/).flatten.uniq.inject(Hash.new { |h, k| h[k] = Array.new }) { |h, treatment| 
          (k,v) = treatment.split(/=/)
          h[k].push v
          h
        }

        project_info[:antibodies]      = factors["AbName"].zip(factors["Target"]).map { |pair| pair.join("=>") }
        project_info[:array_platforms] = (factors["Platform"].blank? ? factors["ArrayPlatform"] : factors["Platform"])
        project_info[:compounds]       = factors["SaltConcentration"].map  { |compound| "SaltConcentration=#{compound}" }
        project_info[:rnai_targets]    = treatments["RNAiTarget"]
        stage_info = (project_info["Stage"] || project_info["Stage/Treatment"] || "")
        stage_info_m = stage_info.match(/^(.*):/)
        project_info[:stages]          = stage_info_m.nil? ? stage_info.split(/,\s*/) : [ stage_info_m[1] ]
        project_info["Stage"]          = stage_info_m.nil? ? stage_info.split(/,\s*/) : [ stage_info_m[1] ]
        project_info[:submission_id]   = project_info["Submission ID"].sub(/ .*/, '')

        project_info[:antibodies] = ["N/A"] if project_info[:antibodies].size == 0
        project_info[:array_platforms] = ["N/A"] if project_info[:array_platforms].size == 0
        project_info[:compounds] = ["N/A"] if project_info[:compounds].size == 0
        project_info[:rnai_targets] = ["N/A"] if project_info[:rnai_targets].size == 0
        project_info[:stages] = ["N/A"] if project_info[:stages].size == 0
      }
    else
      freeze_data.each { |project_info|
        project_info[:antibodies] = project_info["Antibody"].split(/, /)
        project_info[:array_platforms] = project_info["Platform"].split(/, /)
        project_info[:compounds] = project_info["Compound"].split(/, /)
        project_info[:rnai_targets] = project_info["RNAi Target"].split(/, /)
        project_info[:stages] = project_info["Stage/Treatment"].split(/, /)
        project_info[:submission_id]   = project_info["Submission ID"].sub(/ .*/, '')

        project_info[:antibodies] = ["N/A"] if project_info[:antibodies].size == 0
        project_info[:array_platforms] = ["N/A"] if project_info[:array_platforms].size == 0
        project_info[:compounds] = ["N/A"] if project_info[:compounds].size == 0
        project_info[:rnai_targets] = ["N/A"] if project_info[:rnai_targets].size == 0
        project_info[:stages] = ["N/A"] if project_info[:stages].size == 0
      }
    end
  end
end

def usage(e = nil)
  $stderr.puts e.message unless e.nil?
  $stderr.puts "  #{$0} <csv_path> <data_path> <output_path>"
end

begin
  r = Renamer.new(ARGV[0], ARGV[1], ARGV[2])
rescue Exception => e
  usage(e)
  exit
end

r.run
