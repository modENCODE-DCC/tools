require 'dbi'
require 'dbd/Pg'
class DBI::DBD::Pg::Database
    def load_type_map
        if File.exists?("type_map.marshal") then
          puts "DBI_PATCH::Loading type map"
          @type_map = Marshal.restore(File.read("type_map.marshal"))
          puts "DBI_PATCH::Done."
          return
        else
          puts "DBI_PATCH::Reading type map from DB"
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
        @type_map.each_key do |key|
            if @type_map[key]["dbi_type"].class == DBI::DBD::Pg::Type::Array
                oid = @type_map[key]["dbi_type"].base_type
                if @type_map[oid]
                    @type_map[key]["dbi_type"] = DBI::DBD::Pg::Type::Array.new(@type_map[oid]["dbi_type"])
                else
                    # punt
                    @type_map[key] = DBI::DBD::Pg::Type::Array.new(DBI::Type::Varchar)
                end
            end
        end
        File.new("type_map.marshal", "w").puts(Marshal.dump(@type_map))
        puts "Created new type map"
    end
end

