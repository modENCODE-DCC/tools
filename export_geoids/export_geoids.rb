#!/usr/bin/ruby

# To be run as a cron job at least once a week
# Must be run in the ruby-on-rails environment

# This script will find released submissions and any geoid_updates.marshal
# files associated with those submissions, and copy them to the
# upload ftp site.

ENV["GEM_HOME"] = "/var/www/gems"
require 'fileutils'
require '/var/www/submit/config/environment'
include GeoidHelper

FTP_DIR = "/modencode/ftp/geoid_updates"
LAST_UPDATED = "Last_Updated_"


# Where to put marshal files of this pi?
def pi_dir(pi)
  lastname = pi.split(",")[0].downcase
  File.join(FTP_DIR, lastname)
end

# Get the marshal file for a submission; return nil if nonexistent
def datadir_path(sub)
    extracted_dir = File.join(ExpandController.path_to_project_dir(sub), "extracted")
    sdrf_path = AttachGeoidsController.find_sdrf(extracted_dir)
    # If no SDRF found, default to extracted and it will fail gracefully
    lookup_dir = sdrf_path.nil? ? extracted_dir : File.dirname(sdrf_path)
    geoid_marshal = File.join(lookup_dir, GEOID_MARSHAL)
    File.exist?(geoid_marshal) ? geoid_marshal : nil
end

def ftp_path(sub)
  File.join(pi_dir(sub.pi), "#{sub.id}.geoid_updates.marshal")
end

released = Project.find_all_by_status(Project::Status::RELEASED)

released.each{|sub|
    # Find the expected marshal file & ftp filename
    datadir = datadir_path(sub)
    next if datadir.nil? # nvm, no geoids
    ftp = ftp_path(sub)
  
    # Copy if it doesn't exist yet, or if it exists
    # but the marshal in the data dir was more recently updated. 
    if File.exist? ftp then 
      if File.mtime(ftp) < File.mtime(datadir) then
        puts "Updating #{sub.id} in #{pi_dir(sub.pi)}."
        FileUtils.cp(datadir, ftp)
      end
    else
      puts "Adding new #{sub.id} in #{pi_dir(sub.pi)}."
      FileUtils.cp(datadir, ftp)
    end

}

# Update the last updated file tag
old_updated = Dir.entries(FTP_DIR).select{|s| s.include? LAST_UPDATED}
FileUtils.touch(File.join(FTP_DIR, "#{LAST_UPDATED}#{Time.now.strftime("%Y-%m-%d_%H-%M")}"))
old_updated.each{|old| FileUtils.rm(File.join(FTP_DIR, old))}
