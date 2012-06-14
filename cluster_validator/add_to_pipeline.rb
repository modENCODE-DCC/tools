#!/usr/bin/ruby

ENV["GEM_HOME"] = "/var/www/gems"
require "/var/www/submit/config/environment"

BASEDIR = "/modencode/raw/tools/cluster_validator"
BATCHDIR = File.join(BASEDIR, "batches")
DATA_DIR = "/modencode/raw/data"
IDLIST_EXTENSION = ".ids"
CLUSTER_OUTPUT_PREFIX = "Modencode_Validate_"
VALIDATE_START_FILENAME = "VALIDATE.START.TIME" 


# Make sure the necessary files are present:
# chadoxml, outputfile, and timestamp file
def validate_file_existence(id)

  currdir = File.join(DATA_DIR, id, "extracted") 

    # Check to make sure all necessary files are present
    # Use Dir.glob since we don't know cluster id
    necessary_files = [
                        "#{id}.chadoxml",
                        "#{CLUSTER_OUTPUT_PREFIX}#{id}.e*",
                        VALIDATE_START_FILENAME
                      ]
    
   necessary_files.each{|filename|
    res = Dir.glob(File.join(currdir, filename))
    if res.empty? then
      puts "#{id}: ERROR Couldn't find #{filename} in #{currdir}: skipping this project!"
      return false
    end
   }
   true
end

def add_to_pipeline(id)
  proj = Project.find(id)
 

  # Project status must be expanded
  curstat = proj.status
  unless curstat == "expanded" then
    puts "#{id}: Project must be in an expanded state. It's currently #{curstat}."
    return 1
  end


  # After this point, the validate command has been irretrievably made

  command = ValidateIdf2chadoxml.new(:project => proj)
  command.save
  puts "Created validate #{command.id}"
  command.command = "performed validate on cluster"
  extracted = File.join(DATA_DIR, id, "extracted")

  logfile = Dir.glob( File.join(extracted, CLUSTER_OUTPUT_PREFIX + id + ".e*")).last
  validatelog = File.open(logfile, "r").readlines.reject{|f| f =~ /add method for creat/}.join ""
  command.stderr = validatelog
  command.stdout = "\n"
  command.status = "validated"
  
  startfile = File.join(extracted, VALIDATE_START_FILENAME)
  
  command.start_time = File.mtime(startfile)
  command.end_time = File.mtime(logfile)
  command.host="cluster"

 command.save 
 command
end

# ##### ==== MAIN CODE ===

# On startup, ensure running as www-data and that there is a valid argument passed
unless ENV["USER"] == "www-data" then
  puts "This must be run sudo user www-data! You are #{ENV["USER"]}."
  exit 1
end
unless ARGV.length == 1 then
  puts "Please provide as a single argument the name of the batch to add to pipeline, eg nicole-jan12"
  exit 1
end

srcfile = File.join( BATCHDIR, ARGV[0] + IDLIST_EXTENSION)
unless File.exist? srcfile then
  puts "Can't find a batch id list #{ARGV[0]}.ids in #{BATCHDIR} to process!"
  exit 1
end

puts "Reading from file #{srcfile}..."

File.open(srcfile, "r").each{|id|
 id.chomp!
 puts "#{id}: checking for chadoxml file."
 unless validate_file_existence(id) then
   next
 end
 puts "#{id}: ready to be added to pipeline."
 res = add_to_pipeline(id)
 puts "#{id}: Added validate command #{res.id}."
 
}

puts "Complete!"
