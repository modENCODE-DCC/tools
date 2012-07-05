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

def load_breakpoint(which_breakpoint, breakpoint_file_path='.')
  breakpoint_file = "breakpoint#{which_breakpoint}.dmp"
  breakpoint_file = File.join(breakpoint_file_path, breakpoint_file)
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

def get_experiment_types(exps,r)
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

def associate_files_with_geo_ids(exps, r)
  print "Associating result files with their GEO ids" ; $stdout.flush
  exps.each { |e|
    data = e["all_data"]
    print "." ; $stdout.flush
    e["GSM"].each { |g|
      print "-" ; $stdout.flush
      associated_files = r.associate_files_with_rep_ids(data, g, e["xschema"])
      associated_files.each { |af|
        puts "Found #{af["value"]} associated with #{g}"
        e["files"].select{ |f| f["value"] == af["value"]}.each {|f| f["properties"]["GEO id"].push(g) }
      }
    }

  }
  return exps
end

def associate_files_with_sra_ids(exps, r)
  print "Associating result files with their SRA ids" ; $stdout.flush
  exps.each { |e|
    data = e["all_data"]
    print "." ; $stdout.flush
    e["sra_ids"].each { |s|
      print "-" ; $stdout.flush
      associated_files = r.associate_files_with_rep_ids(data, s, e["xschema"])
      puts "Found #{associated_files.length} files for #{s}"
      associated_files.each { |af|
        e["files"].select{ |f| f["value"] == af["value"]}.each {|f| f["properties"]["SRA id"].push(s) }
      }
    }

  }
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
    get_properties_flag = true
    if (get_properties_flag) then
      rep_names_for_this_e = Array.new
      e["files"].select{ |f| f["heading"] =~ /Result|Array Data File|Anonymous/ }.each { |f|
        f = r.associate_sample_properties_with_files(data, f, e["xschema"])
        rep_names_for_this_e.push f["properties"]["rep"]
#        puts "attached #{f["properties"]["rep"].pretty_inspect} to #{f["value"]}"
      }
      counter += 1
      rep_names_for_this_e.flatten!
      rep_names_for_this_e.compact!
      rep_names_for_this_e.uniq!
      rep_counter = 0
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

def get_RNAsize_information(exps,r)
  # Get RNAsize
  print "Collecting RNAsize information" ; $stdout.flush
  exps.each { |e|
    print "."; $stdout.flush
    e["rna_size"] = r.get_rnasize(e["xschema"])
    rna_size=e["specimens"].map{|sp|
      sp["attributes"].find_all { |attr|
        ((attr["heading"] =~ /RNA size/i)) }}.flatten.compact if !e["specimens"].nil?
    if (rna_size.length > 0 ) then
      e["rna_size"] = "small"
    end  
  }
  puts "Done."
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

def print_files (exps)
  header = ["id", "filename", "GEO id", "SRA id", "e GEO", "e SRA"]
  puts header.join("\t")
  exps.each { |e|
    subid = e["xschema"].match(/_(\d+)_/)[1]
    subid += " deprecated by #{e["deprecated"]}" if e["deprecated"]
    subid += " superseded by #{e["superseded"]}" if e["superseded"]
    e["status"] = "superseded" if e["superseded"]
    e["status"] = "deprecated" if e["deprecated"]
    geo_ids = [e["GSE"]]
    geo_ids += e["GSM"] unless e["GSM"].nil?
    sra_ids = e["sra_ids"].sort.join(",") unless e["sra_ids"].nil?
    geo_ids = geo_ids.compact.uniq.reject { |id| id.empty? }.sort.join(", ")

    e["files"].each { |f|
      o = Array.new
      o.push subid
      o.push f["value"]
      if f["properties"].nil? then
        o.push "NO PROPS"
        o.push ""
        o.push ""
        o.push ""
      else
        o.push f["properties"]["GEO id"]
        o.push f["properties"]["SRA id"]
        o.push geo_ids
        o.push sra_ids
      end
      puts o.join("\t")
    }
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

def get_SDRF_from_IDF(idf_path,e)
  idf = File.new(idf_path, "r")
  sdrf_path = ""
  while (line = idf.gets)
  #get the sdrf filename
    if line.match(/SDRF/) then
      sdrf_line = line.chomp
      sdrf_filename = sdrf_line.split("\t")[1]
      sdrf_path = File.join(e["root_path"], sdrf_filename)
    end
  end
  idf.close
  return sdrf_path
end

def get_replicate_sets_from_SDRF(exps)
  print "Getting replicate set information from SDRF files..."
  exps.each { |e|
    print "." ; $stdout.flush
    #get the idf file
    idf_path = File.find(e["root_path"], "*idf*")
    idf_path += File.find(e["root_path"], "*IDF*")
    idf_path = idf_path.first
    sdrf_path = get_SDRF_from_IDF(idf_path,e)

    if sdrf_path.empty? then
     puts "Can't locate SDRF file from #{idf_path}"
   elsif !File.exist?(sdrf_path) then
     puts "SDRF file #{sdrf_path} can't be found"
   else
     sdrf = File.new(sdrf_path, "r")
     sdrf_header = sdrf.gets
     rep_col = sdrf_header.split("\t").index{|h| h.match(/replicate(\s|_)*(set|group)/i) }
     sample_col = nil
     sample_rep = Hash.new
     if !rep_col.nil? then
#       puts "Replicate Set found in column #{col}"
       #associate a sample and it's replicate
       sample_col = sdrf_header.split("\t").index{ |h| h.match(/Hybridization|Sample|Source/) }
       if sample_col.nil? then
         puts "Can't find sample column by Hybridization or Sample.  Try something else"
       else
         while (line = sdrf.gets)
           #build a hash between the sample and its replicate group
           row = line.chomp.split("\t")
           sample = row[sample_col]
           rep = row[rep_col]
           sample_rep[rep] = Array.new if sample_rep[rep].nil?
           sample_rep[rep].push sample  #assume that a single replicate might have multiple samples
         end
       end
     #puts sample_rep.pretty_inspect
     #add the repsetnumber to the relevant file
     e["files"].each { |f| 
       if !f["properties"].nil? then
         f["properties"]["repset"] = Array.new
         f["properties"]["rep"].each { |n|
           #puts "assigning repset to #{n} for file #{f}"
           f["properties"]["repset"] += sample_rep.find_all{|rep, sample| sample.include?(n) }.map{|r,s| r}
         }
         f["properties"]["repset"].flatten!
         f["properties"]["repset"].compact!
         f["properties"]["repset"].uniq!
       end
     }
     end
     sdrf.close
   end
    #puts e["files"].pretty_inspect
  }
  return exps
  puts "Done."
end

def get_GEO_ids_from_files(exps)
  print "Getting GEO ids from files..."; $stdout.flush
  ids = Array.new
  exps.each { |e|
    print "." ; $stdout.flush
    files = e["files"]
    files.each { |f|
      ids = f["properties"]["GEO id"] if f["properties"]
      e["GSM"] += ids
    }
    e["GSM"].flatten!
  }
  return exps
  puts "Done."
end



def print_rep_numbers(exps)
  header = ["ID", "Rep Set", "Sample Number", "Sample Name", "Filename"]
  puts header.join("\t")
  exps.each { |e|
    subid = e["xschema"].match(/_(\d+)_/)[1]
    subid += " deprecated by #{e["deprecated"]}" if e["deprecated"]
    subid += " superseded by #{e["superseded"]}" if e["superseded"]
    e["status"] = "superseded" if e["superseded"]
    e["status"] = "deprecated" if e["deprecated"]
    e["files"].each { |f|
      repnum = ""
      repnum += "#{f["properties"]["rep_num"].join(",")}" unless f["properties"].nil?
      o = Array.new
      o.push subid
      if f["properties"].nil? then
        o.push ""
        o.push ""
        o.push ""
      else
        o.push f["properties"]["repset"].nil? ? "" : f["properties"]["repset"].join(",")
        o.push f["properties"]["rep_num"].nil? ? "" : f["properties"]["rep_num"].join(",")
        o.push f["properties"]["rep"].nil? ? "" : f["properties"]["rep"].join(",")
      end
      o.push f["value"]
      puts o.join("\t")
    }
  }
end

def print_geo_ids (exps)
  exps.each { |e| 
    subid = e["xschema"].match(/_(\d+)_/)[1]
    subid += " deprecated by #{e["deprecated"]}" if e["deprecated"]
    subid += " superseded by #{e["superseded"]}" if e["superseded"]
    e["status"] = "superseded" if e["superseded"]
    e["status"] = "deprecated" if e["deprecated"]
#    puts e["GSM"].pretty_inspect
    geo_ids = [e["GSE"]]
    geo_ids += e["GSM"].map{|id| id.empty? ? id="MISSING GEO ID" : id }  unless e["GSM"].nil?
    sra_ids = e["sra_ids"].map{|id| id.empty? ? id = "MISSING SRA ID" : id} unless e["sra_ids"].nil?
    geo_ids = geo_ids.compact.uniq.sort.join(", ")
    puts "#{subid}\t#{e["project"]}\t#{geo_ids}\t#{sra_ids}"
  }
end

def check_for_changes_to_projects_in_pipeline (old_exps, old_date, dbh) 
  changed_project_ids = []
  unchanged_exps = Array.new
  print "Checking for changes to projects in pipeline since #{old_date.strftime("%F")}..."
  sth = dbh.prepare("SELECT status, deprecated_project_id, superseded_project_id, created_at, updated_at FROM projects WHERE id = ?")
  changed_exps = old_exps.clone
  old_exps.clone.each { |e|
    print "." ; $stdout.flush
    pipeline_id = e["xschema"].match(/_(\d+)_/)[1].to_i
    sth.execute(pipeline_id)
    (status, deprecated, superseded, created_at, updated_at) = sth.fetch_array
    if status.nil? then
      # Chado entry, but deleted from pipeline
      changed_exps.delete(e)    
      next
    end
    if (Time.parse(updated_at) < old_date) then
      changed_exps.delete(e)
    end
  }    
  sth.finish  
  puts "Done."
  changed_project_ids = changed_exps.map{|e| subid = e["xschema"].match(/_(\d+)_/)[1]}
  puts "Found #{changed_exps.length} changes for the following submissions: #{changed_project_ids.join(",")}."
  return changed_project_ids
end

  
def check_changes_to_chadoxml(old_exps,old_date)
  #just in case a chadoxml file was updated in the filesystem, but the 
  #pipeline wasn't touched
  changed_chadoxml_ids = [416]
  changed_exps = old_exps.clone
  print "Checking for changes to chadoxml files since #{old_date.strftime("%F")}..."
  old_exps.clone.each { |e|
    print "." ; $stdout.flush
    pipeline_id = e["xschema"].match(/_(\d+)_/)[1].to_i
    chadofile = File.join("/modencode/raw/data/", pipeline_id.to_s, "extracted", "#{pipeline_id.to_s}.chadoxml")
    if File.exist?(chadofile) then
      if (File.mtime(chadofile) < old_date) then
        changed_exps.delete(e)
      end
    else
      #if there's no chadoxml file, then i don't really care.  if it was present previously, and now it's not,
      #then it should only be the case if new validates were run and failed, which should
      #be picked up in the other methods check_for_changes_to_projects_in_pipeline
      #so they can be deleted from this set
      changed_exps.delete(e)
    end
  }
  puts "Done."
  changed_chadoxml_ids = changed_exps.map{|e| subid = e["xschema"].match(/_(\d+)_/)[1]}
  puts "Found #{changed_exps.length} changes for the following submissions: #{changed_chadoxml_ids.join(",")}."
  return changed_chadoxml_ids
end

def get_most_recent_breakpoint_dir()
  breakpoint_dirs = Dir.foreach(".").select{|x| x.match(/bps/)}  
  return breakpoint_dirs.select{|x| File.exist?(File.join(x,"breakpoint10.dmp"))}.sort{|x,y| File.mtime(x) <=> File.mtime(y)}.last 
end

def get_data_types(exps, r)
  print "Getting data types..." ; $stdout.flush
  exps.each { |e|
    print "." ; $stdout.flush
    e["data_type"] = r.get_data_type(e["xschema"]).map { |type| type == "" ? nil : type }.compact
  }
  puts "Done."
  return exps
end


################################
#            MAIN              #
################################

MAKE_BREAKPOINTS = true #a simple flag to trigger making breakpoints
#TESTING_IDS = [40]
#TESTING_IDS = [90,3180,40,43,2887]
#TESTING_IDS = [40,44,90,127,984,202,43,2887, 2905,2821,2835,4595,4462,4065,2832,2551]
#TESTING_IDS = [40,43,44]
#TESTING_IDS = [21,22,23,24,27,34,35,36,37,40,43,44,48,49,50,51,52,53,54,55,56,57,58,59,60,93,94,95]
#TESTING_IDS = [416,401,411,605,606,654,710,741,778,856,409,375,338,330]
#TESTING_IDS = [401,416]
TESTING_IDS = [774,4208,4215,4214,4322,4290,4291]  #small RNAs
#TESTING_IDS = [584,2866, 2867,2868,342,3420,790,791,910,897,973,4237]
#TESTING_IDS = [3420]
STARTING_BREAKPOINT = 10
FINAL_BREAKPOINT = 10
USE_PREVIOUS_RUN = true
FILE_TYPES = ["Browser_Extensible_Data_Format 6 (BED6+3)", "Browser_Extensible_Data_Format (BED)", "Signal_Graph_File", "WIG", "CEL", "nimblegen_microarray_data_file (pair)", "agilent_raw_microarray_data_file (TXT)", "raw_microarray_data_file", "FASTQ", "SFF", "CSFASTA", "GFF3", "Sequence_Alignment/Map (SAM)", "Binary Sequence_Alignment/Map (BAM)"]

r = ChadoReporter.new
r.set_schema("reporting")

dbinfo = pipeline_database
dbh = DBI.connect(dbinfo[:dsn], dbinfo[:user], dbinfo[:password])

exps = load_breakpoint(10, "bps.2012-05-14")

exps = select_subset(exps, TESTING_IDS)
#avail_schemas = r.get_available_experiments.map{|ae| ae["xschema"]}
#avail_exps = Array.new
#unavail_exps = Array.new
#exps.each { |e|
#  avail_schemas.include?(e["xschema"]) ?
#    avail_exps += [e] : unavail_exps += [e]
#}


#puts "#{avail_exps.length} available for updating}"
#puts "#{unavail_exps.length} unavailable for updating}"
exps = get_RNAsize_information(exps, r)
#exps = get_RNAsize_information(avail_exps, r)
#exps = get_data_types(avail_exps,r)
#exps += unavail_exps
#File.open("new_testin_breakpoint.dmp", 'w') { |f| Marshal.dump(exps, f) }


#exps = get_experiment_types(exps,r)

#ids = exps.map{|e| e["xschema"].match(/_(\d+)_/)[1].to_i}.select{|id| id < 100}
#exps = select_subset(exps, ids)

#exps = determine_seq_method(exps)
#exps = get_read_counts(exps)
#exps = get_experiment_types(exps)
#exps = get_files(exps)
#exps = get_root_paths(exps)
#exps = get_labels(exps,r)
#exps = clean_up_labels(exps)
#exps = associate_files_and_attributes(exps, r)
#exps = get_GEO_ids_from_files(exps)
#exps = associate_files_with_geo_ids(exps, r)
#exps = associate_files_with_sra_ids(exps, r)
#exps = get_samples_and_replicates(exps)
#exps = figure_out_replicate_sets(exps,r)
#exps = get_replicate_sets_from_SDRF(exps)

print "Sorting..."
exps.sort! { |e1, e2| e1["xschema"].match(/_(\d+)_/)[1].to_i <=> e2["xschema"].match(/_(\d+)_/)[1].to_i }
puts "Done."

#print_rep_numbers(exps)
#print_files(exps)
#print_geo_ids(exps)

exps.each { |e|
  subid = e["xschema"].match(/_(\d+)_/)[1]
  puts "#{subid}\t#{e["types"].join(",")}\t#{e["experiment_types"].join(",")}\t#{e["data_type"]}\t#{e["rna_size"]}"
}



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


#print labels
#exps.each { |e|
#  subid = e["xschema"].match(/_(\d+)_/)[1]
#  subid += " deprecated by #{e["deprecated"]}" if e["deprecated"]
#  subid += " superseded by #{e["superseded"]}" if e["superseded"]
#  e["status"] = "superseded" if e["superseded"]
#  e["status"] = "deprecated" if e["deprecated"]
#  e["files"].each { |f|
#    label = f["properties"].nil? ? "" : f["properties"]["label"].nil? ? "" : f["properties"]["label"].map{|l| l.nil? ? "" : l["value"]}.uniq.join(",")
#    #label = f["label"].nil? ? "" : f["label"].map{|l| l.nil? ? "NIL" : l["value"]}.uniq.join(",")
#    #puts f.pretty_inspect
#    puts "#{subid}\t#{f["value"]}\t#{label}"
#  }
#}

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

if ARGV[0] && ARGV[0].length > 0 && Formatter.respond_to?("format_#{ARGV[0]}") then
  Formatter::send("format_#{ARGV[0]}", exps, ARGV[1])
  elsif ARGV[0] && ARGV[0].length > 0 then
  $stderr.puts "Unknown option: #{ARGV[0]}"
  $stderr.puts "  Usage:"
  $stderr.puts "    ./make_report.rb [" + Formatter.methods.find_all { |m| m =~ /^format_/ }.map { |m| m.match(/^format_(.*)/)[1] }.join(", ") + "] [outputfile]"
  else
 #Formatter::format_html(exps, ARGV[1])
end

