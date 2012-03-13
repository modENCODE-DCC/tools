#!/usr/bin/ruby

$:.unshift(File.dirname(__FILE__))

require 'rubygems'
require 'cgi'
require 'yaml'
patch_file = File.join(File.dirname(__FILE__), "dbi_patch.rb")
if File.exists?(patch_file) then
    require 'dbi_patch.rb'
else
    require 'dbi'
      require 'dbd/Pg'
end
require 'pp'

require 'formatter'
require 'chado_reporter'
require 'geo'
require 'escape'

DBI::DBD::Pg::Database::type_map_dir = File.dirname(__FILE__)

module Enumerable
  def uniq_by
    h = {}; inject([]) { |a,x| h[yield(x)] ||= a << x }
  end
end

class File
  def self.find(dir, filename="*.*", subdirs=true)
    Dir[ subdirs ? File.join(dir.split(/\\/), "**", filename) : File.join(dir.split(/\\/), filename) ]
  end
end

def pipeline_database
  if File.exists? "/var/www/submit/config/database.yml" then
    db_def = open("/var/www/submit/config/database.yml") { |f| YAML.load(f.read) }["development"]
    dbinfo = Hash.new
    dbinfo[:dsn] = "dbi:Pg:dbname=#{db_def['database']};host=#{db_def['host']};port=5432"
    dbinfo[:user] = db_def['username']
    dbinfo[:password] = db_def['password']
    return dbinfo
  else
    raise Exception.new("You need a database.yml file in your config/ directory with at least a Ruby DBI dsn.")
  end
end

def load_breakpoint(which_breakpoint)
  breakpoint_file = "breakpoint#{which_breakpoint}.dmp"
  puts "loading #{breakpoint_file}"
  exps = Marshal.load(File.read(breakpoint_file))
  puts "Done."
  puts "#{exps.length} submissions loaded"
  return exps
end

def determine_seq_method(exps)
  print "Figuring out sequencing methods"
  exps.each { |e|
    print "." ; $stdout.flush
    e["sequencer_type"] = Array.new
    e["seq_protocols"] = Array.new
    protocol_types = e["protocol_types"]
    e["seq_protocols"] = e["protocol_types"].nil? ? [] : protocol_types.find_all { |pt| pt["type"] =~ /sequencing(_| )?(protocol|assay)?/ }
    if e["seq_protocols"].empty? then
      e["sequencer_type"].push "NO SEQ PROTOCOL"
    else
      illumina = e["seq_protocols"].find_all{|p| p["description"] =~ /Illumina|GA|HiSeq|Genome Analyzer|Solexa/i}
      solid = e["seq_protocols"].find_all{|p| p["description"] =~ /SOLiD|ABI/i}
      lifetech454 = e["seq_protocols"].find_all{|p| p["description"] =~ /454/i}
      e["sequencer_type"] = Array.new
      e["sequencer_type"].push "Illumina" if illumina.length>=1
      e["sequencer_type"].push "SOLiD" if solid.length >= 1
      e["sequencer_type"].push "454" if lifetech454.length >= 1
      e["sequencer_type"].push "other" if (illumina + solid + lifetech454).empty?
    end
  }
  puts "Done."
  return exps
end

def get_read_counts(exps)
  print "Getting read counts"
  exps.each{ |e| 
    print "."; $stdout.flush

    counts = r.get_read_counts_for_schema(e["xschema"])

    e["read_count"] = counts.sum unless counts.nil? 
  }
  puts "Done."
  return exps
end

def get_experiment_types(exps)
 print "Getting experiment types"
  exps.each { |e|
    print "."; $stdout.flush
    #protocol_types = e["protocol_types"].map { |row| row["type"] }
    e["experiment_types"] = r.get_assay_type(e["xschema"]).map { |type| type == "" ? nil : type }.compact # Is it in the DB?
    if e["experiment_types"].size > 0 && !e["experiment_types"][0].empty? then
      # Use existing assay type
      type = e["experiment_types"][0]
    end
  }
  puts "Done."
  return exps
end

def get_files(exps)
  #incomplete file types

  print "Getting files"
  exps.each { |e|
    data = r.get_data_for_schema(e["xschema"])
    e["all_data"] = data
    print "." ; $stdout.flush
    e["files"] = r.collect_files(data, e["xschema"])
    print "-"*e["files"].length; $stdout.flush
  }
  puts "Done"
  return exps
end

def get_root_file_paths (exps)
  print "Getting root file paths"
  exps.each { |e|
    subid = e["xschema"].match(/_(\d+)_/)[1] 
    #figure out where idf file is in each experiment
    #right now this will be hackily done by looking in the directory
    #should be done by looking at the project files & choosing the active one
    #or looking at the validate command that was successfully run.  anyway...
    
    root_path = "/modencode/raw/data/#{subid}/extracted"
    idf_path = File.find(root_path, "*idf*")
    idf_path += File.find(root_path, "*IDF*")
    idf_path = idf_path.first
    root_path = File.dirname(idf_path) unless idf_path.nil?
    puts "#{subid}\t#{root_path}"
    e["root_path"] = root_path
  }
  puts "Done"

  return exps
end


def associate_files_and_attributes(exps, r)
  counter = 0
  print "Associating result files with their attributes" ; $stdout.flush
  exps.each { |e|
    data = r.get_data_for_schema(e["xschema"])
    print "."; $stdout.flush
    get_properties_flag = (e["antibodies"].length > 0) ||
      (e["GSM"].length > 0 ) ||
      (e["labels"].length > 0)
    if (get_properties_flag) then
      rep_names_for_this_e = Array.new
      e["files"].select{ |f| f["heading"] =~ /Result|Array Data File/ }.each { |f|
        f = r.associate_sample_properties_with_files(data, f, e["xschema"])
        rep_names_for_this_e.push f["properties"]["rep"]
      }
      counter += 1
      rep_names_for_this_e.flatten!
      rep_names_for_this_e.compact!
      rep_names_for_this_e.uniq!
      #puts rep_names_for_this_e.pretty_inspect
      rep_counter = 0
      #TODO: do something different if there's only no rep info found
      rep_names_for_this_e.sort.each { |rep_name|
        #assign the replicate number to the file based on the match between the rep name
        rep_counter += 1
        e["files"].find_all{|f| !f["properties"].nil?}.find_all {|f| f["properties"]["rep"].include?(rep_name)}.each{|f| 
          f["properties"]["rep_num"].push rep_counter
          f["properties"]["rep_num"].delete("TBD")
        }
      }  
    else
      if e["experiment_types"].find {|et| et =~ /ChIP/} then
        puts "#{e["xschema"]} has no antibodies, and is a ChIP"
        e["files"].select{ |f| f["heading"] =~ /Result/ }.each { |f|
          f["properties"] = { f["antibodies"] => Array.new }

        }
      else
      end
    end
  }
  puts "Done."
  puts "#{counter} experiments associated"
  return exps
end



def get_samples_and_replicates (exps)
  print "Getting samples and replicates"
  exps.each { |e| 
    data = r.get_data_for_schema(e["xschema"])
    stuff = data.find_all { |d| d["heading"] =~ /Sample/i || d["name"] =~ /replicate/i}
    stuff += data.find_all { |d| attr = d["attributes"] ; (attr["heading"] =~ /Sample/i || attr["name"] =~ /replicate/i) unless a
    if e["xschema"] =~ /21/ then
      puts stuff.pretty_inspect
    end
    print "."; $stdout.flush
    }
  }
  puts "Done"
  return exps
end

def select_subset (exps, ids)
  exps = exps.select{|e| subid = e["xschema"].match(/_(\d+)_/)[1]; ids.include?(subid.to_i) }
  puts "Selected #{exps.length} submissions for testing: #{ids.join(",")}"
  return exps
end


def print_read_counts_by_platform (exps)
  tallies = Hash.new
  #need to only keep released ones
  exps.each { |e|
    if !tallies.keys.include?(e["sequencer_type"]) then
      tallies[e["sequencer_type"]] = Hash.new
      tallies[e["sequencer_type"]]["read_count"] = 0
      tallies[e["sequencer_type"]]["sub_count"] = 0
      tallies[e["sequencer_type"]]["zero_count"] = 0
    end
    if !e["read_count"].nil?
      tallies[e["sequencer_type"]]["read_count"] += e["read_count"].to_i
      tallies[e["sequencer_type"]]["sub_count"] += 1
      tallies[e["sequencer_type"]]["zero_count"] += 1 if e["read_count"].to_i == 0
    end
  }
  puts "Seq type\tTotal Reads\tSub count\tZero count"
  tallies.each { |type,vals| 
    puts "#{type}\t#{vals["read_count"]}\t#{vals["sub_count"]}\t#{vals["zero_count"]}"
  }
end

def get_labels(exps, r)
  print "Collecting labels"
  exps.each { |e|
    print "."; $stdout.flush
    data = e["all_data"]
    e["labels"] = r.collect_labels(data, e["xschema"])
  }
  puts "Done."
  return exps
end

def clean_up_labels(exps)
  print "Cleaning up sample labels"
  exps.each { |e|
    print "."; $stdout.flush
    e["files"].each { |f|
      if !f["properties"].nil? then
        if !f["properties"]["label"].nil? then
          f["properties"]["label"].each { |l|
            new_label = l["value"].match(/(Cy(3|5)?|Biotin|BrdU)/)
            if !new_label.nil? then
              l["value"] = new_label[0]
            end
          }
        end
      end
    }
  }
  puts "Done."
  return exps
end


################################
#            MAIN              #
################################

MAKE_BREAKPOINTS = true #a simple flag to trigger making breakpoints
TESTING_IDS = [90,3180,40,43]
#TESTING_IDS = [40,44,90,127,984,202,43,2887, 2905,2821,2835,4595,4462,4065,2832,2551]
#TESTING_IDS = [40,43,44]
#TESTING_IDS = [21,22,23,24,27,34,35,36,37,40,43,44,48,49,50,51,52,53,54,55,56,57,58,59,60,93,94,95]

STARTING_BREAKPOINT = 10
FILE_TYPES = ["Browser_Extensible_Data_Format 6 (BED6+3)", "Browser_Extensible_Data_Format (BED)", "Signal_Graph_File", "WIG", "CEL", "nimblegen_microarray_data_file (pair)", "agilent_raw_microarray_data_file (TXT)", "raw_microarray_data_file", "FASTQ", "SFF", "CSFASTA", "GFF3", "Sequence_Alignment/Map (SAM)", "Binary Sequence_Alignment/Map (BAM)"]

r = ChadoReporter.new
r.set_schema("reporting")

dbinfo = pipeline_database
dbh = DBI.connect(dbinfo[:dsn], dbinfo[:user], dbinfo[:password])

exps = load_breakpoint(STARTING_BREAKPOINT)
#ids = exps.map{|e| e["xschema"].match(/_(\d+)_/)[1].to_i}.select{|id| id < 100}
exps = select_subset(exps, TESTING_IDS)
#exps = select_subset(exps, ids)

#exps = determine_seq_method(exps)
#exps = get_read_counts(exps)
#exps = get_experiment_types(exps)
#exps = get_files(exps)
#exps = get_root_paths(exps)
#exps = get_labels(exps,r)
exps = clean_up_labels(exps)
#exps = associate_files_and_attributes(exps, r)
#exps = get_samples_and_replicates(exps)


print "Sorting..."
exps.sort! { |e1, e2| e1["xschema"].match(/_(\d+)_/)[1].to_i <=> e2["xschema"].match(/_(\d+)_/)[1].to_i }
puts "Done."

#exps.each { |e|
#  subid = e["xschema"].match(/_(\d+)_/)[1]
#  subid += " deprecated by #{e["deprecated"]}" if e["deprecated"]
#  subid += " superseded by #{e["superseded"]}" if e["superseded"]
#  e["status"] = "superseded" if e["superseded"]
#  e["status"] = "deprecated" if e["deprecated"]
#  ps = e["seq_protocols"].map{|p| "#{p["type"]}:#{p["name"]}"}.join(" | ")
#  if e["experiment_types"].join(",") =~ /seq/ then
#    geo_ids = [e["GSE"]]
#    geo_ids += e["GSM"] unless e["GSM"].nil?
#    geo_ids += e["sra_ids"] unless e["sra_ids"].nil?
#    geo_ids = geo_ids.compact.uniq.reject { |id| id.empty? }.sort.join(", ")
#    puts "#{subid}\t#{e["project"]}\t#{e["experiment_types"].join(", ")}\t#{e["types"]}\t#{e["sequencer_type"].join(",")}\t#{e["status"]}\t#{e["read_count"]}\t#{geo_ids}\t#{e["uniquename"]}"
#    #puts "#{subid}\t#{e["uniquename"]}\t#{e["project"]}\t#{e["status"]}\t#{e["read_count"]}\t#{geo_ids}"   
#  end
#}

#print rep number
#exps.each { |e|
#  subid = e["xschema"].match(/_(\d+)_/)[1]
#  subid += " deprecated by #{e["deprecated"]}" if e["deprecated"]
#  subid += " superseded by #{e["superseded"]}" if e["superseded"]
#  e["status"] = "superseded" if e["superseded"]
#  e["status"] = "deprecated" if e["deprecated"]
#  e["files"].each { |f|
#    repnum = ""
#    repnum += "#{f["properties"]["rep_num"].join(",")}" unless f["properties"].nil?
#    puts "#{subid}\t#{f["value"]}\t#{repnum.nil? ? "UH OH" : repnum}\t#{f["properties"].nil? ? "" : f["properties"]["rep"]}"
#  }
#}


#print labels
exps.each { |e|
  subid = e["xschema"].match(/_(\d+)_/)[1]
  subid += " deprecated by #{e["deprecated"]}" if e["deprecated"]
  subid += " superseded by #{e["superseded"]}" if e["superseded"]
  e["status"] = "superseded" if e["superseded"]
  e["status"] = "deprecated" if e["deprecated"]
  e["files"].each { |f|
    label = f["properties"].nil? ? "" : f["properties"]["label"].nil? ? "" : f["properties"]["label"].map{|l| l.nil? ? "" : l["value"]}.uniq.join(",")
    #label = f["label"].nil? ? "" : f["label"].map{|l| l.nil? ? "NIL" : l["value"]}.uniq.join(",")
    #puts f.pretty_inspect
    puts "#{subid}\t#{f["value"]}\t#{label}"
  }
}

#print_read_counts_by_platform(exps)

#exps.each { |e|
#  e["files"].each { |f|
#  puts "#{e["xschema"].match(/_(\d+)_/)[1]}\t#{f["value"]}\t#{f["antibodies"].nil? ? "NIL ANTIBODIES" : f["antibodies"].map{|a| a.nil? ? "NIL value" : a["value"]}.join(" | ") }\t#{e["root_path"]}/#{f["value"]}"
#  }
#}

#exps.map { |e|
#  puts "#{e["xschema"]}\t#{e["experiment_types"].join(" ")}\t#{e["read_count"]}\t#{e["files"].length} files"
#}

#puts exps.pretty_inspect
