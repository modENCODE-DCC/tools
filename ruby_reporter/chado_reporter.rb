require 'rubygems'
if File.exists?('dbi_patch.rb') then
  require 'dbi_patch.rb'
else
  require 'dbi'
  require 'dbd/Pg'
end
require 'pp'

class ChadoReporter
  def initialize
    @dbh = DBI.connect("dbi:Pg:dbname=modencode_chado;host=modencode-db1;port=5432", "db_public", "ir84#4nm") unless @dbh
  end
  def dbh
    @dbh
  end
  def set_schema(schema = "public")
    @dbh.do("SET search_path = #{schema};")
  end
  def init_reporting_function
    query = %/
      CREATE OR REPLACE FUNCTION reporting.mkviewswithexptname(set_schemas name[], temporary boolean) RETURNS void AS $$
        DECLARE
         tables NAME[];
         views NAME[];
         schemas NAME[];
         schema_and_table TEXT[];
         mkview TEXT;
        BEGIN
         IF set_schemas IS NULL THEN
           SELECT ARRAY(SELECT DISTINCT tablename FROM pg_tables WHERE schemaname LIKE 'modencode_experiment_%_data') INTO tables;
           SELECT ARRAY(SELECT DISTINCT viewname FROM pg_views WHERE schemaname LIKE 'modencode_experiment_%_data') INTO views;
           SELECT ARRAY(SELECT DISTINCT schemaname FROM pg_tables WHERE schemaname LIKE 'modencode_experiment_%_data' UNION SELECT DISTINCT schemaname from pg_views WHERE schemaname LIKE 'modencode_experiment_%_data') INTO schemas;
           RAISE NOTICE 'Using all modencode_experiment_..._default schemas: %', array_to_string(schemas, ', ');
         ELSE
           SELECT ARRAY(SELECT DISTINCT tablename FROM pg_tables WHERE schemaname = ANY(set_schemas)) INTO tables;
           SELECT ARRAY(SELECT DISTINCT viewname FROM pg_views WHERE schemaname = ANY(set_schemas)) INTO views;
           SELECT ARRAY(SELECT DISTINCT schemaname FROM pg_tables WHERE schemaname = ANY(set_schemas) UNION SELECT DISTINCT schemaname FROM pg_views WHERE schemaname = ANY(set_schemas)) INTO schemas;
         END IF;
         IF array_lower(schemas,1) IS NULL THEN
           RAISE NOTICE 'No schemas found to create views from.';
           RETURN;
         END IF;
         tables := tables || views;
         FOR i IN array_lower(tables,1)..array_upper(tables,1) LOOP
           IF temporary IS NULL OR temporary = TRUE THEN
             mkview := 'CREATE OR REPLACE TEMPORARY VIEW ' || tables[i] || ' AS ';
           ELSE
             mkview := 'CREATE OR REPLACE VIEW ' || tables[i] || ' AS ';
           END IF;
           schema_and_table := '{}';
           FOR j IN array_lower(schemas,1)..array_upper(schemas,1) LOOP
             schema_and_table := schema_and_table || ('SELECT *, ''' || schemas[j] || ''' AS xschema FROM ' || schemas[j] || '.' || tables[i]);
           END LOOP;
           mkview := mkview || array_to_string(schema_and_table, ' UNION ') || ';';
           EXECUTE mkview;
         END LOOP;
        END
      $$ LANGUAGE plpgsql;
    /
    @dbh.do(query)
    @dbh.commit
  end
  def make_reporting_views(temporary = true)
    @dbh.do("SELECT mkviewswithexptname(null, #{temporary ? "true" : "false"})")
    @dbh.commit unless temporary
  end
  def get_feature_types(schema)
    sth = @dbh.prepare("
      SELECT cvt.name AS type FROM #{schema}.cvterm cvt 
      INNER JOIN #{schema}.feature f ON f.type_id = cvt.cvterm_id 
      GROUP BY cvt.name
    ")
    sth.execute
    ret = sth.fetch_all.map { |row| row[0] }
    sth.finish
    return ret
  end

  def get_number_of_features_of_type(schema, type)
    sth = @dbh.prepare("SELECT COUNT(f.*) FROM #{schema}.feature f INNER JOIN #{schema}.cvterm cvt ON f.type_id = cvt.cvterm_id WHERE cvt.name = ?")
    sth.execute(type)
    ret = sth.fetch_array[0]
    sth.finish
    return ret
  end

  def get_assay_type(schema)
    sth = @dbh.prepare("SELECT value FROM #{schema}.experiment_prop WHERE name = 'Assay Type'")
    sth.execute
    ret = sth.fetch_array
    sth.finish
    if ret.nil?
      return [] 
    else
      return [ ret[0] ]
    end
  end

  def get_geo_ids_for_schema(schema)
    sth = @dbh.prepare("
      SELECT d.value FROM #{schema}.data d INNER JOIN #{schema}.cvterm cvt ON d.type_id = cvt.cvterm_id
      WHERE cvt.name = 'GEO_record'
    ")
    sth.execute
    ret = sth.fetch_array
    ret = Array.new if ret.nil?
    sth.finish
    return ret.flatten
  end


  def get_data_for_schema(schema)
    sth = @dbh.prepare("
      SELECT d.data_id, d.heading, d.name, d.value, cv.name || ':' || cvt.name AS type, db.name || ':' || dbx.accession AS dbxref FROM #{schema}.data d
      INNER JOIN #{schema}.cvterm cvt ON d.type_id = cvt.cvterm_id
      INNER JOIN #{schema}.cv ON cvt.cv_id = cv.cv_id
      LEFT JOIN (
        #{schema}.dbxref dbx
        INNER JOIN #{schema}.db db ON dbx.db_id = db.db_id
      ) ON dbx.dbxref_id = d.dbxref_id
      WHERE (d.heading, d.name) IN (
        SELECT d2.heading, d2.name FROM #{schema}.data d2 GROUP BY d2.heading, d2.name HAVING COUNT(d2.data_id) < 80
      )
    ")
    sth.execute
    ret = sth.fetch_all.map { |row| row.to_h }
    sth.finish
    return ret
  end

  def get_experimental_factors_for_schema(schema)
    sth = @dbh.prepare("
      SELECT ep.value AS name, db.name AS xschema, db.url FROM 
      #{schema}.experiment_prop ep
      INNER JOIN #{schema}.dbxref dbx ON ep.dbxref_id = dbx.dbxref_id
      INNER JOIN #{schema}.db ON dbx.db_id = db.db_id
      WHERE db.description = 'modencode_submission'
    ")
    sth.execute
    ret = sth.fetch_all.map { |row| row.to_h }
    sth.finish
    ret.each { |row| 
      if row["url"] =~ /^\d+$/ then
        row["xschema"] = "modencode_experiment_#{row["url"]}_data"
      else
        row["xschema"].sub!(/modencode_submission_(\d+)$/, 'modencode_experiment_\1_data') 
      end
    }
    return ret
  end

  def get_referenced_factor_for_schema(schema, name, value = nil)
    sth = nil
    if value then
      sth = @dbh.prepare("
        SELECT d.data_id, d.heading, d.name, d.value, cv.name || ':' || cvt.name AS type FROM #{schema}.data d
        INNER JOIN #{schema}.cvterm cvt ON d.type_id = cvt.cvterm_id
        INNER JOIN #{schema}.cv ON cvt.cv_id = cv.cv_id
        WHERE d.name = ? AND d.value = ?
      ")
      sth.execute(name, value)
    else
      sth = @dbh.prepare("
        SELECT d.data_id, d.heading, d.name, d.value, cv.name || ':' || cvt.name AS type FROM #{schema}.data d
        INNER JOIN #{schema}.cvterm cvt ON d.type_id = cvt.cvterm_id
        INNER JOIN #{schema}.cv ON cvt.cv_id = cv.cv_id
        WHERE d.name = ?
      ")
      sth.execute(name)
    end
    ret = sth.fetch_all.map { |row| row.to_h }
    sth.finish

    ret.clone.each do |row|
      older_data = self.get_older_data(schema, row["data_id"])
      while older_data.size > 0
        ret += older_data
        older_ids = older_data.map { |d| d["data_id"] }
        older_data = Array.new
        older_ids.each { |oid|
          older_data += get_older_data(schema, oid)
        }
      end
    end

    # Recurse into even older submissions
    ret = { schema => ret }
    referenced_factors = self.get_experimental_factors_for_schema(schema)
    referenced_factors.each { |factor|
      puts "      Getting (recursed) reference from #{schema} to #{factor["xschema"]}"
      ret = ret.merge(self.get_referenced_factor_for_schema(factor["xschema"], factor["name"], value))
      puts "      Done."
    }
    return ret
  end

  def get_referenced_data_for_schema(schema, name, value)
    sth = @dbh.prepare("
      SELECT d.data_id, d.heading, d.name, d.value, cv.name || ':' || cvt.name AS type FROM #{schema}.data d
      INNER JOIN #{schema}.cvterm cvt ON d.type_id = cvt.cvterm_id
      INNER JOIN #{schema}.cv ON cvt.cv_id = cv.cv_id
      WHERE d.name = ? AND d.value = ?
    ")
    sth.execute(name, value)
    ret = sth.fetch_all.map { |row| row.to_h }
    sth.finish

    ret.clone.each do |row|
      older_data = self.get_older_data(schema, row["data_id"])
      while older_data.size > 0
        ret += older_data
        older_ids = older_data.map { |d| d["data_id"] }
        older_data = Array.new
        older_ids.each { |oid|
          older_data += get_older_data(schema, oid)
        }
      end
    end
    return ret
  end
  
  def get_older_data(schema, data_id)
    # Make this query get any data from the current protocol or previous so's to get any leading here
    # Then, in make_report, use the data_id to pull specimens out of the old experiment
    sth = @dbh.prepare("
      SELECT d.data_id, d.heading, d.name, d.value, cv.name || ':' || cvt.name AS type FROM #{schema}.data d
      INNER JOIN #{schema}.cvterm cvt ON d.type_id = cvt.cvterm_id
      INNER JOIN #{schema}.cv ON cvt.cv_id = cv.cv_id
      INNER JOIN #{schema}.applied_protocol_data apd_older ON d.data_id = apd_older.data_id AND apd_older.direction = 'input'
      INNER JOIN #{schema}.applied_protocol ap ON apd_older.applied_protocol_id = ap.applied_protocol_id
      INNER JOIN #{schema}.applied_protocol_data apd_newer ON ap.applied_protocol_id = apd_newer.applied_protocol_id AND apd_newer.direction = 'output'
      WHERE apd_newer.data_id = ?
    ")
    sth.execute(data_id)
    ret = sth.fetch_all.map { |row| row.to_h }
    sth.finish
    return ret
  end

  def get_protocol_types_for_data_ids(data_ids, schema)
    sth = @dbh.prepare("SELECT DISTINCT a.value AS type, p.name, p.description FROM #{schema}.attribute a 
      INNER JOIN #{schema}.protocol_attribute pa ON a.attribute_id = pa.attribute_id
      INNER JOIN #{schema}.protocol p ON p.protocol_id = pa.protocol_id
      INNER JOIN #{schema}.applied_protocol ap ON p.protocol_id = ap.protocol_id
      INNER JOIN #{schema}.applied_protocol_data apd ON ap.applied_protocol_id = apd.applied_protocol_id
      WHERE a.heading = 'Protocol Type' AND apd.data_id = ANY(?)
    ")
    sth.execute(data_ids)
    ret = sth.fetch_all.map { |row| row.to_h }
    sth.finish
    return ret
  end

  def get_attributes_for_datum(data_id, schema)
    sth = @dbh.prepare("
      SELECT attr.attribute_id, attr.heading, attr.name, attr.rank, attr.value, cv.name || ':' || cvt.name AS type, attr.dbxref_id AS attr_group 
      FROM #{schema}.attribute attr 
      INNER JOIN #{schema}.data_attribute da ON attr.attribute_id = da.attribute_id 
      LEFT JOIN ( #{schema}.cvterm cvt
        INNER JOIN #{schema}.cv ON cvt.cv_id = cv.cv_id
      ) ON attr.type_id = cvt.cvterm_id
      WHERE da.data_id = ?
    ")
    sth.execute(data_id)
    ret = sth.fetch_all.map { |row| row.to_h }
    sth.finish
    return ret
  end
  
  def get_organisms_for_experiment(schema)
    sth = @dbh.prepare("SELECT organism_id, genus, species FROM #{schema}.organism")
    sth.execute
    possible_organisms = sth.fetch_all.map { |row| row.to_h }
    sth.finish
    sth = @dbh.prepare("SELECT * FROM #{schema}.feature WHERE organism_id = ? LIMIT 1")
    organisms = possible_organisms.find_all { |o| 
      sth.execute(o["organism_id"])
      !sth.fetch_array.nil?
    }
    sth.finish
    organisms = possible_organisms unless organisms.size > 0
    organisms.each { |o| o.delete("organism_id") }
    return organisms
  end

  def get_available_experiments
    sth_schemas = @dbh.prepare("SELECT DISTINCT schemaname FROM pg_tables WHERE schemaname LIKE 'modencode_experiment_%_data'")
    sth_schemas.execute
    ret = Array.new
    sth_schemas.fetch_hash { |row|
      sth = @dbh.prepare("SELECT experiment_id, uniquename, description FROM #{row["schemaname"]}.experiment")
      sth.execute
      h =  sth.fetch_hash
      next if h.nil?
      sth.finish
      h["xschema"] = row["schemaname"]
      ret.push h
    }
    sth_schemas.finish
    return ret
  end

  def get_experiment_properties(schema)
    sth = @dbh.prepare("SELECT ep.name, ep.rank, ep.value, cv.name || ':' || cvt.name AS type, db.name || ':' || dbx.accession AS dbxref 
                        FROM #{schema}.experiment_prop ep 
                        LEFT JOIN (#{schema}.cvterm cvt INNER JOIN #{schema}.cv ON cvt.cv_id = cv.cv_id) ON cvt.cvterm_id = ep.type_id 
                        LEFT JOIN (#{schema}.dbxref dbx INNER JOIN #{schema}.db ON db.db_id = dbx.db_id) ON dbx.dbxref_id = ep.dbxref_id
                       ")
    sth.execute
    ret = sth.fetch_all.map { |row| row.to_h }
    sth.finish
    return ret
  end

  def get_protocol_types(schema)
    sth = @dbh.prepare("SELECT DISTINCT a.value AS type, p.name, p.description FROM #{schema}.attribute a 
      INNER JOIN #{schema}.protocol_attribute pa ON a.attribute_id = pa.attribute_id
      INNER JOIN #{schema}.protocol p ON p.protocol_id = pa.protocol_id
      WHERE a.heading = 'Protocol Type'
    ")
    sth.execute
    ret = sth.fetch_all.map { |row| row.to_h }
    sth.finish
    return ret
  end



  ################################################
  # Data collection methods
  ################################################
  def get_basic_experiments
    self.set_schema("reporting")
    # Generate PostgreSQL functions for querying all of the submissions at once
#    self.init_reporting_function
#    self.make_reporting_views(false)

    # Get a list of all the experiments (and their properties)
    exps = self.get_available_experiments
    exps.each do |experiment|
      print "."
      $stdout.flush
      experiment["types"] = self.get_feature_types(experiment["xschema"])
    end
    print "\n"

    exps.delete_if { |e|
      # Ignore schema 0
      e["xschema"] =~ /^modencode_experiment_(0)_data$/ #||
    }


    return exps
  end

  def get_nice_types(types)
    # Get all of the feature types for each experiment, and from them
    # generate a list of "nice" type names. For instance, types containing
    # "intron", "exon", "start_codon", "stop_codon" are all categorized as
    # "splice sites"
    nice_types = Array.new

    # "splice sites"
    found_types = types.find_all { |type|
      type =~ /^(intron|exon)(_.*)?$/ ||
      type =~ /^(start|stop)_codon$/
    }
    if found_types.size > 0 then
      nice_types.push "splice sites"
      types -= found_types
    end

    # "transcription/coding junctions"
    found_types = types.find_all { |type|
      type =~ /CDS|UTR/ ||
      type =~ /^TSS$/ ||
      type =~ /^transcription_end_site$/
    }
    if found_types.size > 0 then
      nice_types.push "transcription/coding junctions"
      types -= found_types
    end

    # "alignments"
    found_types = types.find_all { |type| type =~ /(.*_)?match(_.*)?/ }
    if found_types.size > 0 then
      nice_types.push "alignments"
      types -= found_types
    end

    # "trace reads"
    found_types = types.find_all { |type| type =~ /^TraceArchive_record$/ }
    if found_types.size > 0 then
      nice_types.push "trace reads"
      types -= found_types
    end

    # "gene models"
    found_types = types.find_all { |type|
      type =~ /^(gene|transcript|mRNA)$/
    }
    if found_types.size > 0 then
      nice_types.push "gene models"
      types -= found_types
    end

    # "transcript fragments"
    found_types = types.find_all { |type|
      type =~ /^(transcript_region)$/
    }
    if found_types.size > 0 then
      nice_types.push "transcript fragments"
      types -= found_types
    end
    # "gene models"
    found_types = types.find_all { |type|
      type =~ /^(gene|transcript|mRNA)$/
    }
    if found_types.size > 0 then
      nice_types.push "gene models"
      types -= found_types
    end

    # "binding sites"
    found_types = types.find_all { |type|
      type =~ /^(.*_)?binding_site$/
    }
    if found_types.size > 0 then
      nice_types.push "binding sites"
      types -= found_types
    end

    # "origins of replication"
    found_types = types.find_all { |type| type =~ /^origin_of_replication$/ }
    if found_types.size > 0 then
      nice_types.push "origins of replication"
      types -= found_types
    end

    # "copy number variation"
    found_types = types.find_all { |type| type =~ /^copy_number_variation$/ }
    if found_types.size > 0 then
      nice_types.push "copy number variation"
      types -= found_types
    end

    # "EST alignments"
    found_types = types.find_all { |type|
      type =~ /^(EST|overlapping_EST_set)$/
    }
    if found_types.size > 0 then
      nice_types.push "EST alignments"
      types -= found_types
    end

    # "cDNA alignments"
    found_types = types.find_all { |type|
      type =~ /cDNA/
    }
    if found_types.size > 0 then
      nice_types.push "cDNA alignments"
      types -= found_types
    end

    # Accept but skip display of chromosomes/sequence regions
    found_types = types.find_all { |type|
      type =~ /^(chromosome(_.*)?)$/ ||
      type =~ /^region$/
    }
    types -= found_types

    # Keep the original types for anything we didn't translate above
    nice_types += types
    return nice_types
  end

  def unescape(str)
    str = CGI.unescapeHTML(str)
    match = str.match(/^"([^"]*)"/)
    match.nil? ? str : match[1]
  end

  # Get any specimens (cell line, strain, stage, array) attached to this experiment;
  # requires the correct type(s) (see regex below and filters to make sure it
  # matches the expected style for specimen data

  def collect_specimens(data, xschema)
#    specimens = data.find_all { |d| d["type"] =~ /MO:((whole_)?organism(_part)?)|(developmental_)?stage|(worm|fly)_development:|RNA|cell(_line)?|strain_or_line|BioSample|modencode:ADF|MO:genomic_DNA|SO:RNAi_reagent|MO:GrowthCondition|modencode:ShortReadArchive_project_ID(_list)? \(SRA\)|MO:CellLine|modencode:GEO_record/ }
    specimens = data
    missing = Array.new
    filtered_specimens = Array.new
    # Make sure that the data we've found of these types actually matches an
    # expected template for cell lines, strains, or stages
    specimens.each { |d|
      attrs = self.get_attributes_for_datum(d["data_id"], xschema)
      if !( 
           attrs.find { |a| a["heading"] == "official name" }.nil? && 
           attrs.find { |a| a["heading"] == "Cell Type cv" }.nil? &&
           attrs.find { |a| a["heading"] == "developmental stage" }.nil? &&
           attrs.find { |a| a["heading"] == "strain" }.nil? 
          ) then
        # This datum has an attribute with one of the above headings.  All of
        # the headings being checked are from the wiki, and as such are
        # somewhat controlled by templates
        d["attributes"] = attrs
        filtered_specimens.push d
      elsif attrs.find { |attr| attr["type"] == "modencode:reference" } then
        # This datum references a datum in an older submission (as with the
        # Celinker RNA samples), so we'll keep it in case it turns out to be an
        # antibody, strain, stage, or cell line
        ref_attr = attrs.find_all { |attr| attr["type"] == "modencode:reference" }
        d["attributes"] = attrs
        filtered_specimens.push d
      elsif attrs.find { |attr| attr["heading"] =~ /Characteristics?/ } then
        d["attributes"] = attrs
        filtered_specimens.push d
      elsif d["heading"] =~ /Anonymous Datum/ && d["type"] =~ /MO:((whole_)?organism(_part)?)/ then
        # Occasionally we don't specify the piece of the organism that is
        # collected except as an anonymous output between two protocols. This
        # serves to capture at least whether we've got a whole organism or part
        # of one
        d["attributes"] = Array.new
        filtered_specimens.push d
      elsif d["type"] =~ /MO:(whole_)?organism/ then
        d["attributes"] = attrs
        filtered_specimens.push d
      elsif d["type"] =~ /developmental_stage/ then
        d["attributes"] = attrs
        filtered_specimens.push d
      elsif d["type"] =~ /modencode:ADF/ then
        d["attributes"] = attrs
        filtered_specimens.push d
      elsif d["type"] =~ /SO:RNAi_reagent/ then
        d["attributes"] = attrs
        filtered_specimens.push d
      elsif d["type"] =~ /MO:GrowthCondition/ then
        d["attributes"] = nil
        filtered_specimens.push d
      elsif attrs.find { |a| a["type"] =~ /MO:Compound/i } then
        d["attributes"] = attrs
        filtered_specimens.push d
      elsif d["type"] =~ /modencode:ShortReadArchive_project_ID(_list)? \(SRA\)/ then
        d["attributes"] = nil
        filtered_specimens.push d
      elsif attrs.find { |a| a["heading"] == "RNA ID" } then
        # Ignore RNA collections
      elsif d["value"].length == 0
        # Ignore empty (probably anonymous) cells
      elsif d["type"] == "modencode:GEO_record"
        # Ignore GEO records that aren't references to old submissions
      else
        # Track any specimens that didn't fall into one of the above categories
        # so we can add support for them to the code.
        missing.push d
      end
    }
    # Make sure the list of specimens is unique
    filtered_specimens = filtered_specimens.uniq_by { |d| d["attributes"].nil? ? d["value"] : d["attributes"] }

    missing = missing.find_all { |d| d["type"] =~ /MO:((whole_)?organism(_part)?)|(developmental_)?stage|(worm|fly)_development:|RNA|cell(_line)?|strain_or_line|BioSample|modencode:ADF|MO:genomic_DNA|SO:RNAi_reagent|MO:GrowthCondition|modencode:ShortReadArchive_project_ID(_list)? \(SRA\)|MO:CellLine|modencode:GEO_record/ }
    # Whine about any missing specimens
    if missing.size > 0 then
      if missing.size > 1 then
        missing = missing[0...2].map { |d| d["value"] + " (#{d["type"]})" }.join(", ") + ", and #{missing.size - 2} more"
      else
        missing = missing[0]["value"] + " (#{missing[0]["type"]})"
      end
      puts "Unknown type of specimen: #{missing} for submission #{xschema}"
    end

    return filtered_specimens

  end

  # Get any antibodies attached to this experiment; requires the correct type
  # (MO:antibody) and for it to be from a wiki page with an "official name" field
  def collect_antibodies(data, xschema)
    filtered_antibodies = Array.new
    antibodies = data.find_all { |d| d["type"] =~ /MO:(antibody)/ }
    antibodies.each { |d|
      attrs = self.get_attributes_for_datum(d["data_id"], xschema)
      unless attrs.find { |a| a["heading"] == "official name" }.nil? then
        d["attributes"] = attrs
        filtered_antibodies.push d
      end
    }
    filtered_antibodies = filtered_antibodies.uniq_by { |d| d["attributes"].nil? ? nil : d["attributes"] }
    return filtered_antibodies
  end

  def collect_compounds(data, xschema)
    filtered_compounds = Array.new
    compounds = data.find_all { |d| d["type"] =~ /MO:Compound/ }
    compounds.each { |d|
      attrs = self.get_attributes_for_datum(d["data_id"], xschema)
      d["attributes"] = attrs
      filtered_compounds.push d
    }
    filtered_compounds = filtered_compounds.uniq_by { |d| d["attributes"].nil? ? nil : d["attributes"] }
    return filtered_compounds
  end

  # Get any microarrays attached to this experiment; requires the correct type
  # (modencode:ADF) and for it to be from a wiki page with an "official name"
  # field
  def collect_microarrays(data, xschema)
    filtered_arrays = Array.new
    arrays = data.find_all { |d| d["type"] =~ /modencode:(ADF)/ }
    arrays.each { |d|
      attrs = self.get_attributes_for_datum(d["data_id"], xschema)
      unless attrs.find { |a| a["heading"] == "official name" }.nil? then
        d["attributes"] = attrs
        filtered_arrays.push d
      end
    }
    filtered_arrays = filtered_arrays.uniq_by { |d| d["attributes"].nil? ? nil : d["attributes"] }
    return filtered_arrays
  end

  def collect_gff(schema)
    sth = @dbh.prepare("
                       SELECT d.value FROM #{schema}.data d
                       INNER JOIN #{schema}.cvterm cvt ON d.type_id = cvt.cvterm_id
                       WHERE cvt.name = 'GFF3'
                       GROUP BY d.value
                       ")
    sth.execute
    gffs = sth.fetch_all.flatten
    sth.finish
    return gffs
  end

  def collect_sam(schema)
    sth = @dbh.prepare("
                       SELECT d.value FROM #{schema}.data d
                       INNER JOIN #{schema}.cvterm cvt ON d.type_id = cvt.cvterm_id
                       WHERE cvt.name = 'Sequence_Alignment/Map (SAM)'
                       GROUP BY d.value
                       ")
    sth.execute
    sams = sth.fetch_all.flatten
    sth.finish
    return sams
  end

  def recursively_find_referenced_specimens(curschema, specimens, all_specimens = Hash.new { |h,k| h[k] = Array.new } )
    referenced_specimens = specimens.find_all { |sp| sp["attributes"] && sp["attributes"].find { |attr| attr["type"] == "modencode:reference" } }
    # Save all the unreferencd specimens as members of this schema
    all_specimens[curschema] += (specimens - referenced_specimens)
    referenced_specimens.each { |refspecimen|
      old_experiment_id = refspecimen["attributes"].find { |attr| attr["type"] == "modencode:reference" }["value"].split(/:/)[0]
      xschema = "modencode_experiment_#{old_experiment_id}_data"
      puts "Finding reference to #{xschema}:#{refspecimen["value"]}"
      potential_old_specimens = self.backtrack_datum_graph(xschema, refspecimen)
      old_specimens = self.collect_specimens(potential_old_specimens, xschema)
      self.recursively_find_referenced_specimens(xschema, old_specimens, all_specimens)
    }
    return all_specimens
  end

  def backtrack_datum_graph(schema, refspecimen)
    return self.get_referenced_data_for_schema(schema, refspecimen["name"], refspecimen["value"])
  end
end

