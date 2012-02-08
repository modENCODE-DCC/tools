require 'rubygems'
require 'dbi'
require 'dbd/Pg'
class DBI::DBD::Pg::Database
    def self.type_map_num
      @type_map_num ||= 0
      @type_map_num += 1
    end
    def self.type_map_dir=(new_dir)
      @type_map_dir = new_dir
    end
    def self.type_map_dir
      @type_map_dir
    end
    def load_type_map
        @type_map_counter ||= DBI::DBD::Pg::Database::type_map_num
        filename = "type_map_#{@type_map_counter}.marshal"
        filename = File.join(DBI::DBD::Pg::Database::type_map_dir, filename) if DBI::DBD::Pg::Database::type_map_dir
        if File.exists?(filename) then
          puts "DBI_PATCH::Loading type map #{@type_map_counter}"
          @type_map = Marshal.restore(File.read(filename))
          puts "DBI_PATCH::Done."
          return
        else
          puts "DBI_PATCH::Reading type map from DB #{@type_map_counter}"
        end
        @type_map = Hash.new

        res = _exec("SELECT oid, typname, typelem FROM pg_type WHERE typtype IN ('b', 'e')")

        res.each do |row|
            rowtype = parse_type_name(row["typname"])
            @type_map[row["oid"].to_i] = 
                { 
                    "type_name" => row["typname"],
                    "dbi_type" => 
                        if rowtype
                            rowtype
                        elsif row["typname"] =~ /^_/ and row["typelem"].to_i > 0 then
                            # arrays are special and have a subtype, as an
                            # oid held in the "typelem" field.
                            # Since we may not have a mapping for the
                            # subtype yet, defer by storing the typelem
                            # integer as a base type in a constructed
                            # Type::Array object. dirty, i know.
                            #
                            # These array objects will be reconstructed
                            # after all rows are processed and therefore
                            # the oid -> type mapping is complete.
                            # 
                            DBI::DBD::Pg::Type::Array.new(row["typelem"].to_i)
                        else
                            DBI::Type::Varchar
                        end
                }
        end 
        # additional conversions
        @type_map[705]  ||= DBI::Type::Varchar       # select 'hallo'
        @type_map[1114] ||= DBI::Type::Timestamp # TIMESTAMP WITHOUT TIME ZONE

        # remap array subtypes
        need_to_add_composites = Hash.new
        @type_map.each_key do |key|
            if @type_map[key]["dbi_type"].class == DBI::DBD::Pg::Type::Array
                oid = @type_map[key]["dbi_type"].base_type
                if @type_map[oid]
                    @type_map[key]["dbi_type"] = DBI::DBD::Pg::Type::Array.new(@type_map[oid]["dbi_type"])
                else
                    # punt
                    @type_map[key] = DBI::DBD::Pg::Type::Array.new(DBI::Type::Varchar)
                    if !@type_map[oid] then
                        # Oops, no underlying type (composite?)
                        need_to_add_composites[oid.to_i] = { "dbi_type" => DBI::DBD::Pg::Type::Array.new(DBI::Type::Varchar) }
                    end
                end
            end
        end
        @type_map.merge!(need_to_add_composites)
        File.new(filename, "w").puts(Marshal.dump(@type_map))
        puts "Created new type map"
    end
end

