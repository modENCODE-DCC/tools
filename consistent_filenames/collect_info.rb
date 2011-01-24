#!/usr/bin/ruby

require 'file_finder'
require 'marshal_cache'
require 'pp'
require 'rubygems'
require 'dbi'

ROOT_DIR = "/archive/golden/data/srv/www/data/pipeline"
CACHE_DIR = "cache"

def db
  @db = DBI.connect("DBI:Pg:dbname=modencode_chado;host=awol.lbl.gov;port=5433", "db_public", "ir84#4nm") unless @db
  return @db
end


files_by_experiment = Hash.new { |h, experiment_id| h[experiment_id] = Hash.new }
DBI.convert_types = false
@ff = FileFinder.new(ROOT_DIR)
@cache = MarshalCache.new(CACHE_DIR)

experiment_ids = [ 2252 ]
exp_id = 2252

#experiment_ids.each { |exp_id|

# Get the actual files in the project's extracted directory
if @cache["files"]
  files = @cache["files"]
else
  files = @ff.get_files_for_exp(exp_id)
  @cache["files"] = files
end

# Get anything that looks like a file from the database
if @cache["db_files"]
  db_files = @cache["db_files"]
else
  sth = db.prepare("SELECT data_id, value FROM modencode_experiment_#{exp_id}_data.data
                   WHERE
                   REGEXP_REPLACE(value, '.*/', '') = ANY(?)
                   OR heading IN ('Result File', 'Parameter File')")
  sth.execute("{" + files.map { |f| DBI::DBD::Pg.quote(File.basename(f)) }.join(", ") + "}" )

  db_files = Array.new
  sth.fetch_hash { |row|
    db_files.push row
  }
  @cache["db_files"] = db_files
end

# Best effort at matching up real files to DB files


puts db_files.pretty_inspect

#}
