require 'fileutils'
require 'find'
class FileFinder
  def initialize(root)
    @root_folder = root
  end
  def get_files_for_exp(exp_id)
    exp_id = exp_id.to_s
    exp_dir = File.join(@root_folder, exp_id, "extracted")
    files = Array.new
    Find.find(exp_dir) do |path|
      files.push path if File.file?(path)
    end

    files
  end
end
