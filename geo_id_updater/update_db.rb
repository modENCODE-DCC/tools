#!/usr/bin/ruby
require 'rubygems'
require 'dbi'
require 'common_funcs.rb'
require 'dbi_patch.rb' if File.exists?('dbi_patch.rb')
require 'pp'

NO_DB_COMMITS = true
db = DBI.connect("DBI:Pg:modencode_chado:modencode-db.oicr.on.ca", "db_public", "ir84#4nm")
db.execute("BEGIN TRANSACTION") if NO_DB_COMMITS

if !ARGV[0] then
  $stderr.puts "Usage:"
  $stderr.puts "  ./update_db.rb --from-list=marshal_list.txt"
  $stderr.puts "  ./update_db.rb <outdir>/50/template.config [ <outdir>/50/template.config ... ]"
  exit
elsif ARGV[0] =~ /^--from-list=/ then
  list = ARGV[0].match(/--from-list=(.*)/)[1]
  if !File.exists?(list) then
    $stderr.puts "No such list file #{list}"
    exit
  end
  marshal_list = File.read(list).split($/).map { |f| 
    if f =~ /^\// then
      f
    else
      File.join(File.dirname(list), f)
    end
  }
else
  marshal_list = ARGV
end

marshal_list.each { |f|
  if !File.exists?(f) then
    $stderr.puts "No such marsharled file: #{f}"
    exit
  end
}

marshal_list.each do |file|
  info = Marshal.restore(File.open(file))

  pid = info[:pid]
  geo_header_col = info[:geo_header_col]
  geo_record = info[:geo_record]
  previous_protocol_name = info[:previous_protocol_name]

  puts "UPDATING #{pid} on protocol '#{previous_protocol_name}'"

  db.execute("SET search_path = modencode_experiment_#{pid}_data")
  if (geo_header_col) then
    puts "  Found an existing GEO datum; updating it and creating new ones as necessary"
    sth_get_existing_record = db.prepare("SELECT apd.applied_protocol_data_id, apd.direction, apd.applied_protocol_id, d.data_id, d.value FROM applied_protocol_data apd INNER JOIN data d ON apd.data_id = d.data_id WHERE d.heading = ? AND d.name = ? ORDER BY data_id")
    sth_get_existing_record.execute(geo_header_col.heading, geo_header_col.name)
    geo_id_data = Array.new
    sth_get_existing_record.fetch_hash { |row|
      geo_id_data.push(row)
    }
    sth_get_existing_record.finish

    unique_data = geo_id_data.map { |r| r["data_id"] }.uniq
    if geo_id_data.size == geo_record.values.size || geo_id_data.size == geo_record.values.uniq.size then
      # Perfect, they line up... Do we have to create more datums?

      if geo_id_data.size == geo_record.values.uniq.size then
        geo_record.values.uniq!
      end

      if unique_data.size != 1 then
        if unique_data.size == geo_record.values.size then
          geo_record.values.each_index { |i| geo_id_data[i]["value"] = geo_record.values[i] }
        else
          # Are the IDs already in there?
          values = geo_id_data.map { |d| d["value"] }
          if values.sort == geo_record.values.sort then
            puts "      All GEO IDs already in this submission!"
            next
          else
            throw :more_than_one_unique_datum 
          end
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
          puts "    Creating datum for #{d["value"]}"
          sth_create.execute(data_info["name"], data_info["heading"], d["value"], data_info["type_id"], data_info["dbxref_id"])
          sth_last_data_id.execute
          last_id = sth_last_data_id.fetch_hash["last_value"]
          sth_update_applied_protocol_data.execute(last_id, d["applied_protocol_data_id"])
        else
          # Update existing datum
          puts "    Updating existing datum for #{d["value"]}"
          sth_update.execute(d["value"], d["data_id"])
        end
        n += 1
      }
      sth_create.finish
      sth_update.finish
      sth_last_data_id.finish
      sth_update_applied_protocol_data.finish
    else
      puts "      More (or fewer) applied protocols using a GEO ID than GEO IDs to attach."
      sth_update = db.prepare("UPDATE data SET value = ? WHERE data_id = ?")
      if unique_data.size == geo_record.values.size then
        puts "        However, there are as many unique datum(s) as GEO IDs to attach."
        sorted_data_ids = unique_data.sort
        sorted_data_ids.each_index { |i|
          data_id = sorted_data_ids[i]
          v = geo_record.values[i]
          puts "        Updating datum to #{v}."
          sth_update.execute(v, data_id)
        }
      elsif geo_record.values.uniq.size == 1
        puts "        However, there is only 1 GEO ID to attach, so it is the same for all of them."
        sorted_data_ids = unique_data.sort
        v = geo_record.values.first
        if geo_id_data.first["value"] == v then
          puts "          Actually, that ID is already in the DB"
        else
          sorted_data_ids.each { |data_id|
            puts "        Updating datum to #{v}."
            sth_update.execute(v, data_id)
          }
        end
      else
        puts "        Fewer applied protocols for the datum than we expected:"
        puts geo_id_data.pretty_inspect
        puts "!=!=!="
        puts geo_record.values.pretty_inspect
        throw :wtf_they_dont_line_up
      end
      sth_update.finish
    end
  else
    puts "  No existing GEO datum, creating it/them"
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
    elsif geo_record.values.uniq.size == 1 then
      # Okay, there's only one GSM so we apply it to all APs
      gsm = geo_record.values.first
      use_these_gsms = existing_aps.map { gsm }
    else
      puts "    #{existing_aps.size} APs for #{geo_record.values.size} GEO records"
      throw :ap_size_differs_from_geo_record_count
    end
    # Create a new datum for each geo record in order and attach it to each applied_protocol as an output
    if use_these_gsms.size != existing_aps.size then
      throw :wtf_i_thought_i_just_set_ap_sizes
    end

    geo_type_id = get_geo_type_id(db)

    sth_create_data = db.prepare("INSERT INTO data (heading, name, value, type_id) VALUES(?, ?, ?, ?)")
    sth_create_apd = db.prepare("INSERT INTO applied_protocol_data (applied_protocol_id, data_id, direction) VALUES(?, ?, 'output')")
    sth_last_data_id = db.prepare("SELECT last_value FROM generic_chado.data_data_id_seq")
    sth_datum_exists = db.prepare("SELECT data_id FROM data WHERE (name = 'geo record' or name = 'GEO id') AND value = ?")
    sth_apd_exists = db.prepare("SELECT applied_protocol_data_id FROM applied_protocol_data WHERE applied_protocol_id = ? AND data_id = ?")

    existing_aps.each_index { |i|
      ap = existing_aps[i]
      gsm = use_these_gsms[i]
      sth_datum_exists.execute(gsm)
      data_row = sth_datum_exists.fetch_hash
      if data_row then
        puts "    Already a datum for #{gsm}"
        data_id = data_row["data_id"]
      else
        puts "    Creating a datum for #{gsm}"
        sth_create_data.execute("Result Value", "geo record", gsm, geo_type_id)
        sth_last_data_id.execute
        data_id = sth_last_data_id.fetch_hash["last_value"]
      end
      sth_apd_exists.execute(ap["applied_protocol_id"], data_id)
      if sth_apd_exists.fetch_hash then
        puts "      Already and applied_protocol_datum for #{gsm} and #{ap["applied_protocol_id"]}"
      else
        puts "      Creating applied_protocol_data entry for #{gsm} and #{ap["applied_protocol_id"]}"
        sth_create_apd.execute(ap["applied_protocol_id"], data_id)
      end
    }
    sth_create_data.finish
    sth_create_apd.finish
    sth_last_data_id.finish
    sth_datum_exists.finish
    sth_apd_exists.finish
  end
end

db.execute("ROLLBACK") if NO_DB_COMMITS
db.disconnect
