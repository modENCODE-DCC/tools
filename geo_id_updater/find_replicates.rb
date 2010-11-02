#!/usr/bin/ruby
require 'fileutils'
require 'pp'
require 'rubygems'
require 'dbi'
require 'dbi_patch.rb'
require 'common_funcs.rb'

NO_DB_COMMITS = true

def parse_sdrf(filename)
  f = File.open(filename)

  has_quotes = false
  header = f.readline.chomp.split(/\t/).map { |k| 
    has_quotes = true if (k =~ /^"|"$/)
    SDRFHeader.new(k.gsub(/^"|"$/, ''))
  }
  header.each { |s| s.has_quotes! } if has_quotes

  f.each { |line|
    line.chomp!
    #num_at = Hash.new { |h, k| h[k] = Hash.new { |h1, k1| h1[k1] = 0 } }
    items = line.split(/\t/).map { |k| k.gsub(/^"|"$/, '') }
    items.each_index { |i|
      header[i].add_split(items[i])
      header[i].values.push items[i]
    }
  }

  header
end
def print_sdrf(sdrf, outfile)
  has_quotes = true if sdrf.find { |h| h.has_quotes? }
  throw :not_overwriting if (outfile && File.exists?(outfile))
  f = outfile.nil? ? $stdout : File.new(outfile, "w")
  if has_quotes then
    f.puts sdrf.map { |h| '"' + h.fullname + '"' }.join("\t")
  else
    f.puts sdrf.map { |h| h.fullname }.join("\t")
  end
  sdrf_rows = sdrf[0].rows
  (0..(sdrf_rows-1)).each { |i|
    if has_quotes then
      f.puts sdrf.map { |h| '"' + h.values[i] + '"' }.join("\t")
    else
      f.puts sdrf.map { |h| h.values[i] }.join("\t")
    end
  }
  f.close
end
def make_chadoxml(h, level = 0)
  h.map { |k, v|
    k = k.sub(/#.*/, '')
    xml = (" "*level) + "<#{k}>"
    if v.is_a?(Hash) then
      xml += "\n" + make_chadoxml(v, level+2) + "\n" + (" "*level)
    else
      xml += v.to_s
    end
    xml += "</#{k.match(/\w*/)[0]}>"
  }.join("\n")
end

if (!ARGV[0] || !ARGV[1]) then
  $stderr.puts "Usage:"
  $stderr.puts "  ./find_replicates.rb <pid_gse_gsm_sdrf.txt> <outdir>"
  $stderr.puts ""
  $stderr.puts "  Where pid_gse_gsm_sdrf is a tab-delimited file of the format:"
  $stderr.puts "    project_id\tGSE####\tGSM###,GSM###,...\t/path/to/project_id/sdrf.txt"
  exit
end
f = File.new(ARGV[0])
out = Dir.new(ARGV[1])
db = DBI.connect("DBI:Pg:modencode_chado:modencode-db.oicr.on.ca", "db_public", "ir84#4nm")
info = {}
marshal_list = File.new(File.join(out.path, "marshal_list.txt"), "w")
f.each { |line|
  line.chomp!
  (pid, gse, gsms, sdrf) = line.split(/\t/)
  gsms = gsms.split(/,/)

  info[:pid] = pid

  header = parse_sdrf(sdrf)
  s = header.reverse

  puts "modencode_#{pid} has #{gsms.size} GSMs"

  enough_replicates_at_colum_idx = s.find_index { |col| col.num_splits == gsms.size }
  if enough_replicates_at_colum_idx.nil? then
    raise Exception.new("Couldn't find #{gsms.size} replicates in SDRF for #{pid}")
  end

  enough_replicates_at = s[enough_replicates_at_colum_idx]
  previous_protocol = s.slice(enough_replicates_at_colum_idx, s.length).find { |col| col.heading =~ /Protocol REF/i }; previous_protocol_name = previous_protocol.split_example unless previous_protocol.nil?
  next_protocol = s.slice(0, enough_replicates_at_colum_idx).reverse.find { |col| col.heading =~ /Protocol REF/i }; next_protocol_name = next_protocol.split_example unless next_protocol.nil?

  geo_header_idx = s.find_index { |h| h.name =~ /geo/i }

  if geo_header_idx then
    previous_protocol = s.slice(geo_header_idx, s.length).find { |col| col.heading =~ /Protocol REF/i }; previous_protocol_name = previous_protocol.split_example unless previous_protocol.nil?
    next_protocol = s.slice(0, geo_header_idx).reverse.find { |col| col.heading =~ /Protocol REF/i }; next_protocol_name = next_protocol.split_example unless next_protocol.nil?
    # Attach GEO IDs to existing GEO ID column
    puts "  Found existing GEO ID column for #{pid} between: '#{previous_protocol_name.to_s}' AND '#{next_protocol_name.to_s}'"
    sdrf_rows = s[geo_header_idx].rows
    geo_header_col = s[geo_header_idx]
    if sdrf_rows != gsms.size then
      # Attach GEO IDs, lining up duplicates with the previous row in the SDRF with the appropriate number of unique values
      puts "    There more rows in the SDRF than GSM IDs: #{sdrf_rows} != #{gsms.size}."
      # Have to line this up carefully
      uniq_rows = enough_replicates_at.uniq_rows
      puts "      Unique rows for #{enough_replicates_at.heading} [#{enough_replicates_at.name}]: " + uniq_rows.pretty_inspect
      geo_header_col.values.clear
      uniq_rows.each_index { |is_idx| 
        uniq_rows[is_idx].each { |i|
          geo_header_col.values[i] = gsms[is_idx]
        }
      }
      puts "      Setting GSMs to: " + geo_header_col.values.join(", ")
    else
      # Attach GEO IDs to the SDRF in order
      geo_header_col.values.clear
      gsms.each_index { |i|
        geo_header_col.values[i] = gsms[i]
      }
      puts "      Setting GSMs to: " + geo_header_col.values.join(", ")
    end
    geo_record = geo_header_col
  else
    # Attach GEO IDs for each unique datum that is enough_replicates_at on the protocol previous_protocol
    sdrf_rows = header[0].rows
    geo_record = SDRFHeader.new("Result Value", "geo record")
    if sdrf_rows != gsms.size then
      puts "    There more rows in the SDRF than GSM IDs: #{sdrf_rows} != #{gsms.size}."
      # Have to line this up carefully
      uniq_rows = enough_replicates_at.uniq_rows
      puts "      Unique rows for #{enough_replicates_at.heading} [#{enough_replicates_at.name}]: " + uniq_rows.pretty_inspect
      uniq_rows.each_index { |is_idx| 
        uniq_rows[is_idx].each { |i|
          geo_record.values[i] = gsms[is_idx]
        }
      }
      puts "      Setting GSMs to: " + geo_record.values.join(", ")
    else
      gsms.each_index { |i|
        geo_record.values[i] = gsms[i]
      }
      puts "      Setting GSMs to: " + geo_record.values.join(", ")
    end

    i = next_protocol.nil? ? header.size : header.find_index(next_protocol)
    header.insert(i, geo_record)
    puts "  Attach GEO IDs to protocol: '#{previous_protocol.to_s}'"
  end

  # Create new SDRF
  FileUtils.mkdir_p(File.join(out.path, pid.to_s))
  out_sdrf = File.join(out.path, pid.to_s, File.basename(sdrf))
  print_sdrf(header, out_sdrf)

  info[:geo_header_col] = geo_header_col
  info[:geo_record] = geo_record
  info[:previous_protocol_name] = previous_protocol_name

  # Database!
  db.execute("SET search_path = modencode_experiment_#{pid}_data")
  if (geo_header_col) then
    sth_get_existing_record = db.prepare("SELECT apd.applied_protocol_data_id, apd.direction, apd.applied_protocol_id, d.data_id, d.value FROM applied_protocol_data apd INNER JOIN data d ON apd.data_id = d.data_id WHERE d.heading = ? AND d.name = ? ORDER BY data_id")
    sth_get_existing_record.execute(geo_header_col.heading, geo_header_col.name)
    geo_id_data = Array.new
    sth_get_existing_record.fetch_hash { |row|
      geo_id_data.push(row)
    }
    sth_get_existing_record.finish

    if geo_id_data.size == geo_record.values.size then
      # Perfect, they line up... Do we have to create more datums?
      unique_data = geo_id_data.map { |r| r["data_id"] }.uniq

      if unique_data.size != 1 then
        if unique_data.size == geo_record.values.size then
          geo_record.values.each_index { |i| geo_id_data[i]["value"] = geo_record.values[i] }
        else
          throw :more_than_one_unique_datum 
        end
      else
        geo_record.values.each_index { |i| geo_id_data[i]["value"] = geo_record.values[i] }
        # Update the existing one and add some more
        # 1. Get current attributes of the existing datum
        sth_get_datum = db.prepare("SELECT * FROM data WHERE data_id = ?")
        sth_get_datum.execute(geo_id_data.first["data_id"])
        data_info = sth_get_datum.fetch_hash
        sth_get_datum.finish
        # 2. Remove data_id from all but first data entry
        geo_id_data[1..-1].each { |d| d["data_id"] = nil }
      end

      # Insert and/or update
      sth_create = db.prepare("INSERT INTO data (name, heading, value, type_id, dbxref_id) VALUES(?, ?, ?, ?, ?)")
      sth_update = db.prepare("UPDATE data SET value = ? WHERE data_id = ?")
      sth_last_data_id = db.prepare("SELECT last_value FROM generic_chado.data_data_id_seq")
      sth_update_applied_protocol_data = db.prepare("UPDATE applied_protocol_data SET data_id = ? WHERE applied_protocol_data_id = ?")
      n=0
      geo_id_data.each { |d|
        if d["data_id"].nil? then
          # Create new datum
          sth_create.execute(data_info["name"], data_info["heading"], d["value"], data_info["type_id"], data_info["dbxref_id"]) unless NO_DB_COMMITS
          sth_last_data_id.execute unless NO_DB_COMMITS
          last_id = sth_last_data_id.fetch_hash["last_value"] unless NO_DB_COMMITS
          sth_update_applied_protocol_data.execute(last_id, d["applied_protocol_data_id"]) unless NO_DB_COMMITS
        else
          # Update existing datum
          sth_update.execute(d["value"], d["data_id"]) unless NO_DB_COMMITS
        end
        n += 1
      }
      sth_create.finish
      sth_update.finish
      sth_last_data_id.finish
      sth_update_applied_protocol_data.finish
    else
      puts "Fewer applied protocols for the datum than we expected:"
      puts geo_id_data.pretty_inspect
      puts "!=!=!="
      puts geo_record.values.pretty_inspect
      throw :wtf_they_dont_line_up
    end

  else
    puts "No existing GEO datum, creating them"
    sth_find_protocol = db.prepare("SELECT ap.applied_protocol_id FROM applied_protocol ap INNER JOIN protocol p ON ap.protocol_id = p.protocol_id WHERE p.name = ? ORDER BY ap.applied_protocol_id")
    sth_find_protocol.execute(previous_protocol_name)
    existing_aps = Array.new
    sth_find_protocol.fetch_hash { |row| existing_aps.push row }
    sth_find_protocol.finish

    if existing_aps.size == geo_record.values.size then
      # Sweet, there are as many APs as geo records
      use_these_gsms = geo_record.values
    elsif existing_aps.size == geo_record.values.uniq.size then
      # Okay, but it works for unique ones
      use_these_gsms = geo_record.values.uniq
    else
      puts "#{existing_aps.size} APs for #{geo_record.values.size} GEO records"
      throw :ap_size_differs_from_geo_record_count
    end
    # Create a new datum for each geo record in order and attach it to each applied_protocol as an output
    if use_these_gsms.size != existing_aps.size then
      throw :wtf_i_thought_i_just_set_ap_sizes
    end
    geo_type_id = get_geo_type_id(db) unless NO_DB_COMMITS

    sth_create_data = db.prepare("INSERT INTO data (heading, name, value, type_id) VALUES(?, ?, ?, ?)")
    sth_create_apd = db.prepare("INSERT INTO applied_protocol_data (applied_protocol_id, data_id, direction) VALUES(?, ?, 'output')")
    sth_last_data_id = db.prepare("SELECT last_value FROM generic_chado.data_data_id_seq")
    sth_datum_exists = db.prepare("SELECT data_id FROM data WHERE name = 'geo record' AND value = ?")

    existing_aps.each_index { |i|
      ap = existing_aps[i]
      gsm = use_these_gsms[i]
      sth_datum_exists.execute(gsm)
      if sth_datum_exists.fetch_hash then
        puts "Already a datum for #{gsm}"
        next
      end
      sth_create_data.execute("Result Value", "geo record", gsm, geo_type_id) unless NO_DB_COMMITS
      sth_last_data_id.execute unless NO_DB_COMMITS
      last_id = sth_last_data_id.fetch_hash["last_value"] unless NO_DB_COMMITS
      sth_create_apd.execute(ap["applied_protocol_id"], last_id) unless NO_DB_COMMITS
    }
    sth_create_data.finish
    sth_create_apd.finish
    sth_last_data_id.finish
    sth_datum_exists .finish
  end
  out_marshal = File.join(out.path, pid.to_s, "template.config")
  f = File.new(out_marshal, "w")
  f.puts(Marshal.dump(info))
  f.close
  marshal_list.puts File.join(pid.to_s, "template.config")
}
marshal_list.close
db.disconnect

