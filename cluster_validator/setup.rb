begin
 x = RAILS_ROOT
rescue
  puts "Please run this in the rails environment: begin the rails console and type
    require '/modencode/raw/tools/cluster_validator/setup'"
  exit
end


require "escape"
require 'yaml'

BASE = "/modencode/raw/tools/cluster_validator/batches"



# This creates a file with a yaml of a hash of the project info.
# also a file with just IDs.
# it will rewrite it on every run.
def createfile(pids)

  # if the pids are actually projects, convert them back to project ids.
  pids.map!{|proj| 
    if proj.class == Project then
      proj.id.to_s
    else
      proj.to_s
     end
    }
    
  pids.sort!{|f, g| f.to_i <=> g.to_i } # for in-order projects yay
  proj_hash = Hash.new
  
  pids.each{|proj|
    name = Project.find(proj).name 
    add_embargo = ""
    # also add an embargo date if necessary
    embargo_end = Project.find(proj).embargo_end_date

    projname = Escape::shell_single_word(name)
    projembargo = Escape::shell_single_word(embargo_end.strftime('%F')) 

    # and add to array
    proj_hash[proj.to_s] = [projname, projembargo]
  }

  # then, write info
  outf = File.open(File.join(BASE, @outfname), "w") # originally tmp/cluster-project-names.
  idoutf = File.open(File.join(BASE,  @outfname + ".ids"), "w")

  outf.puts YAML::dump proj_hash

  idoutf.puts pids.join "\n"

  outf.close
  idoutf.close

  puts "Created list of #{pids.length} projects in batch #{@outfname}. To overwrite this list, run
  createfile( myArrayName) 
  with an array containing desired project ids.
  When done, ssh to xfer.res and run, in screen:
  /modencode/raw/tools/cluster_validator/upload_to_cluster.pl #{@outfname}"

end

###  MAIN CODE ###

puts "Type a short alphabetic string you'll remember for the name of this batch: "

while(true)
@outfname = gets.chomp
  if (File.exist? File.join(BASE, @outfname)) then
    puts "Sorry, #{@outfname} is already taken. Pick another name: "
  elsif(@outfname =~ /\W/) then
    puts "Sorry, #{@outfname} is too confusing. Please use only letters, numbers, or underscores : "
  else
    puts "Ok, now make an array with the project ids you want and run:
    createfile( arrayVariableName)
    to set up the list of project ids."
    break
  end
end



# Output in format:
#pid|PROJECT NAME|embargo date
