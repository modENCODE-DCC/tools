class ChadoReporter
  def initialize
    @dbh = DBI.connect("dbi:Pg:dbname=modencode_chado;host=heartbroken.lbl.gov", "db_public", "ir84#4nm") unless @dbh
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

  def get_data_for_schema(schema)
    sth = @dbh.prepare("
      SELECT d.data_id, d.heading, d.name, d.value, cv.name || ':' || cvt.name AS type FROM #{schema}.data d
      INNER JOIN #{schema}.cvterm cvt ON d.type_id = cvt.cvterm_id
      INNER JOIN #{schema}.cv ON cvt.cv_id = cv.cv_id
      WHERE (d.heading, d.name) IN (
        SELECT d2.heading, d2.name FROM #{schema}.data d2 GROUP BY d2.heading, d2.name HAVING COUNT(d2.data_id) < 80
      )
    ")
    sth.execute
    ret = sth.fetch_all.map { |row| row.to_h }
    sth.finish
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
    sth = @dbh.prepare("SELECT DISTINCT a.value AS type, p.description FROM #{schema}.attribute a 
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
    sth = @dbh.prepare("SELECT experiment_id, uniquename, description, xschema FROM experiment")
    sth.execute
    ret = sth.fetch_all
    sth.finish
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
    sth = @dbh.prepare("SELECT DISTINCT a.value AS type, p.description FROM #{schema}.attribute a 
      INNER JOIN #{schema}.protocol_attribute pa ON a.attribute_id = pa.attribute_id
      INNER JOIN #{schema}.protocol p ON p.protocol_id = pa.protocol_id
      WHERE a.heading = 'Protocol Type'
    ")
    sth.execute
    ret = sth.fetch_all.map { |row| row.to_h }
    sth.finish
    return ret
  end
end

