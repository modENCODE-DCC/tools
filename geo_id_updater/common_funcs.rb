class SDRFHeader
  def initialize(heading, name=nil)
    @num_splits = Hash.new
    @values = Array.new
    if name then
      @heading = heading
      @name = name
      @fullname = @heading + (@name.nil? ? "" : " [#{@name}]")
    else
      m = heading.match(/([^\[]*)(\[(.*)\])?/)
      @heading = m[1].gsub(/^\s*|\s*$/, '')
      @name = m[3]
      @fullname = heading
    end
  end
  def values
    @values
  end
  def heading
    @heading
  end
  def name
    @name
  end
  def fullname
    @fullname
  end
  def rows
    @values.size
  end
  def add_split(item)
    @num_splits[item] = true
  end
  def num_splits
    @num_splits.keys.size
  end
  def split_example
    @num_splits.keys.first
  end
  def uniq_rows
    r = Hash.new
    @values.each_index { |i|
      v = @values[i]
      r[v] ||= Array.new
      r[v].push i
    }
    r.values.sort { |a, b| a[0] <=> b[0] }
  end
  def to_s
    "(#{self.num_splits.to_s})" + @heading + (@name.nil? ? "" : " [#{@name}]") + "==" + self.split_example
  end
  def has_quotes?
    @has_quotes
  end
  def has_quotes!
    @has_quotes = true
  end
end
def get_geo_type_id(db)
  sth_get_cvterm = db.prepare("SELECT cvterm_id FROM cvterm WHERE name = 'GEO_record'")
  sth_get_cv = db.prepare("SELECT cv_id FROM cv WHERE name = 'modencode'")
  sth_get_db = db.prepare("SELECT db_id FROM db WHERE name = 'modencode'")
  sth_get_dbxref = db.prepare("SELECT dbxref_id FROM dbxref INNER JOIN db ON dbxref.db_id = db.db_id WHERE db.name = 'modencode' AND dbxref.accession = '0000109'")

  sth_make_db = db.prepare("INSERT INTO db (name, description, url) VALUES('modencode', 'OBO', 'http://wiki.modencode.org/project/extensions/DBFields/ontologies/modencode-helper.obo')")
  sth_make_dbxref = db.prepare("INSERT INTO dbxref (db_id, accession) VALUES(?, '0000109')")
  sth_make_cv = db.prepare("INSERT INTO cv (name) VALUES('modencode')")
  sth_make_cvterm = db.prepare("INSERT INTO cvterm (cv_id, dbxref_id, name) VALUES(?, ?, 'GEO_record')")

  sth_get_cvterm.execute
  if (row = sth_get_cvterm.fetch_hash) then
    cvterm_id = row["cvterm_id"]
  else
    # Make a CVTerm
    # Got a CV?
    sth_get_cv.execute
    if (row = sth_get_cv.fetch_hash) then
      cv_id = row["cv_id"]
    else
      # Make a CV
      sth_make_cv.execute
      sth_get_cv.execute; row = sth_get_cv.fetch_hash; throw :wtf_no_cv if row.nil?
      cv_id = row["cv_id"]
    end

    # .. and DBXref?
    sth_get_dbxref.execute
    if (row = sth_get_dbxref.fetch_hash) then
      dbxref_id = row["dbxref_id"]
    else
      # Make a dbxref
      # Got a DB?
      sth_get_db.execute
      if (row = sth_get_db.fetch_hash) then
        db_id = row["db_id"]
      else
        # Make a DB
        sth_make_db.execute
        sth_get_db.execute; row = sth_get_db.fetch_hash; throw :wtf_no_db if row.nil?
        db_id = row["db_id"]
      end
      # Make a DBXref
      sth_make_dbxref.execute(db_id)
      sth_get_dbxref.execute; row = sth_get_dbxref.fetch_hash; throw :wtf_no_dbxref if row.nil?
      dbxref_id = row["dbxref_id"]
    end

    # Make a CVTerm
    sth_make_cvterm.execute(cv_id, dbxref_id)
    sth_get_cvterm.execute; row = sth_get_cvterm.fetch_hash; throw :wtf_no_cvterm if row.nil?
    cvterm_id = row["cvterm_id"]
  end

  sth_get_cvterm.execute
  row = sth_get_cvterm.fetch_hash

  # Clean up handles
  sth_get_cvterm.finish; sth_get_cv.finish; sth_get_db.finish; sth_get_dbxref.finish
  sth_make_cvterm.finish; sth_make_cv.finish; sth_make_db.finish; sth_make_dbxref.finish

  throw :wtf_still_no_cvterm if cvterm_id.nil?
  return cvterm_id
end

