class MarshalCache
  def initialize(cache_dir)
    @cache_dir = cache_dir
  end

  def []=(name, obj)
    File.open(File.join(@cache_dir, "#{name}_cache.dmp"), "w" ) { |f|
      f.puts Marshal.dump(obj)
    }
  end

  def [](name)
    filename = File.join(@cache_dir, "#{name}_cache.dmp")
    return nil unless File.exists?(filename)
    File.open(filename, "r" ) { |f|
      Marshal.restore(f.read)
    }
  end
end
