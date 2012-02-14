require 'rubygems'
require '/var/www/submit/config/environment'
class Formatter
  def self.format(exps, collapse_long=true, extra_cols = {})
    cols = [
        "Submission ID",
        "Project",
        "Lab",
        "Organism",
        "Status",
        "Data Type",
        "Assay",
        "Tissue",
        "Strain",
        "Cell Line",
        "Stage/Treatment",
        "Antibody Name",
        "Target",
        "Compound",
        "Temp",
        "Platform",
        "RNAi Target",
        "Date Data Submitted",
        "Release Date",
        "GEO/SRA IDs",
    ] + extra_cols.keys
    if block_given? then
      yield cols
    else
      puts cols.join("\t")
    end
    exps.each do |e|
      cols = Array.new
      id = e["xschema"].match(/_(\d+)_/)[1]
      id += " deprecated by #{e["deprecated"]}" if e["deprecated"]
      id += " superseded by #{e["superseded"]}" if e["superseded"]
      e["status"] = "superseded" if e["superseded"]
      e["status"] = "deprecated" if e["deprecated"]
      cols.push id
      cols.push e["project"]
      cols.push e["lab"]
      cols.push e["organisms"].map { |o| "#{o["genus"]} #{o["species"]}" }.join(", ")
      cols.push e["status"]
      cols.push e["types"].join(", ")
      cols.push e["experiment_types"].join(", ")
      cols.push e["tissue"].join(", ")
      cols.push e["strain"].map { |s| 
        s == "y[1]; Gr22b[1] Gr22d[1] cn[1] CG33964[R4.2] bw[1] sp[1]; LysC[1] MstProx[1] GstD5[1] Rh6[1]" ? "y; cn bw sp" : s 
      }.map { |s| 
        s =~ /y\[1\].*\scn\[1\].*\sbw\[1\].*\ssp\[1\]/ ? "y; cn bw sp" : s 
      }.uniq.sort.join(", ")
      cols.push e["cell_line"].uniq.join(", ")
      if collapse_long then
        cols.push e["stage"].size > 5 ? e["stage"].sort[0..5].join(", ") + ", and #{e["stage"].size-5} more..." : e["stage"].sort.join(", ")
      else
        cols.push e["stage"].sort.join(", ")
      end
      cols.push e["antibody_names"].compact.join(", ")
      #puts "id: #{id}\n#{e.pretty_inspect}"
      cols.push e["antibody_targets"].join(", ")
      cols.push e["compound"].join(", ")
      cols.push e["temp"].join(", ")
      cols.push e["array_platform"].join(", ")
      cols.push e["rnai_targets"].join(", ")
      cols.push e["created_at"]
      cols.push((e["status"] == "released" || e["status"] == "published" || e["status"] == "deprecated" || e["status"] == "superseded") ? e["released_at"] : "")
      geo_ids = [e["GSE"]]
      geo_ids += e["GSM"] unless e["GSM"].nil?
      geo_ids += e["sra_ids"] unless e["sra_ids"].nil?
      cols.push geo_ids.compact.uniq.reject { |id| id.empty? }.sort.join(", ")
      extra_cols.values.each { |colname| cols.push e[colname] }

      if block_given? then
        yield cols
      else
        puts cols.join("\t")
      end
    end
  end
  
  def self.format_files(exps, collapse_long=true, extra_cols = {})
    
    cols = [ "Submission ID",
             "Title",
             "Data File",
             "Data Filepath",
             "Level 4 <File Format>",
             "Lab",
             "Organism",        
             "Status", 
             "Data Type",
             "Assay",
             "Tissue",
             "Strain",
             "Cell Line",        
             "Stage/Treatment",        
             "Antibody Name",        
             "Target",
             "Compound",
             "Temp",
             "Platform",
             "RNAi Target",
             "Date Data Submitted",
             "Release Date",
             "GEO/SRA IDs",
          ] + extra_cols.keys

    if block_given? then
        yield cols
      else
        puts cols.join("\t")
      end

    exps.each do |e|
      cols = Array.new
      subid = e["xschema"].match(/_(\d+)_/)[1]
      subid += " deprecated by #{e["deprecated"]}" if e["deprecated"]
      subid += " superseded by #{e["superseded"]}" if e["superseded"]
      e["status"] = "superseded" if e["superseded"]
      e["status"] = "deprecated" if e["deprecated"]
      files = e["files"]
      if files.nil? then
        cols = Array.new
        cols.push "#{subid}"
        cols.push e["uniquename"]
        cols.push "NO FILES FOUND"
        cols.push e["lab"]
        cols.push e["organisms"].map { |o| "#{o["genus"]} #{o["species"]}" }.join(", ")
        cols.push e["status"]
        cols.push e["types"].join(", ")
        cols.push e["experiment_types"].join(", ")
        cols.push e["tissue"].join(", ")
        cols.push e["strain"].map { |s|
          s == "y[1]; Gr22b[1] Gr22d[1] cn[1] CG33964[R4.2] bw[1] sp[1]; LysC[1] MstProx[1] GstD5[1] Rh6[1]" ? "y; cn bw sp" : s }.map { |s|                  s =~ /y\[1\].*\scn\[1\].*\sbw\[1\].*\ssp\[1\]/ ? "y; cn bw sp" : s }.uniq.sort.join(", ")
        cols.push e["cell_line"].uniq.join(", ")
        if collapse_long then
          cols.push e["stage"].size > 5 ? e["stage"].sort[0..5].join(", ") + ", and #{e["stage"].size-5} more..." : e["stage"].sort.join(", ")
        else
          cols.push e["stage"].sort.join(", ")
        end
        cols.push e["antibody_names"].compact.join(", ")
        #puts "id: #{id}\n#{e.pretty_inspect}"
        cols.push e["antibody_targets"].join(", ")
        cols.push e["compound"].join(", ")
        cols.push e["temp"].join(", ")
        cols.push e["array_platform"].join(", ")      
        cols.push e["rnai_targets"].join(", ")      
        cols.push e["created_at"]      
        cols.push((e["status"] == "released" || e["status"] == "published" || e["status"] == "deprecated" || e["status"] == "superseded") ? e["released_at"] : "")      
        geo_ids = [e["GSE"]]
        geo_ids += e["GSM"] unless e["GSM"].nil?
        geo_ids += e["sra_ids"] unless e["sra_ids"].nil?
        cols.push geo_ids.compact.uniq.reject { |id| id.empty? }.sort.join(", ")
        extra_cols.values.each { |colname| cols.push e[colname] }
       
        if block_given? then
          yield cols
        else
          puts cols.join("\t")
        end
      else
        files.each do |f|
          #assume f is a hash, with name, path, type
          cols = Array.new
          cols.push "#{subid}"
          cols.push e["uniquename"]
          cols.push f["name"]
          cols.push f["path"]
          cols.push f["type"]
          cols.push e["lab"]
          cols.push e["organisms"].map { |o| "#{o["genus"]} #{o["species"]}" }.join(", ")
          cols.push e["status"]
          cols.push e["types"].join(", ")
          cols.push e["experiment_types"].join(", ")
          cols.push e["tissue"].join(", ")
          cols.push e["strain"].map { |s|
            s == "y[1]; Gr22b[1] Gr22d[1] cn[1] CG33964[R4.2] bw[1] sp[1]; LysC[1] MstProx[1] GstD5[1] Rh6[1]" ? "y; cn bw sp" : s }.map { |s| 
            s =~ /y\[1\].*\scn\[1\].*\sbw\[1\].*\ssp\[1\]/ ? "y; cn bw sp" : s }.uniq.sort.join(", ")
          cols.push e["cell_line"].uniq.join(", ")
          if collapse_long then          
            cols.push e["stage"].size > 5 ? e["stage"].sort[0..5].join(", ") + ", and #{e["stage"].size-5} more..." : e["stage"].sort.join(", ")              else          
            cols.push e["stage"].sort.join(", ")
          end                                                 
          cols.push e["antibody_names"].compact.join(", ")
          cols.push e["antibody_targets"].join(", ")
           cols.push e["compound"].join(", ")
           cols.push e["temp"].join(", ")        
           cols.push e["array_platform"].join(", ")        
           cols.push e["rnai_targets"].join(", ")
           cols.push e["created_at"]
           cols.push((e["status"] == "released" || e["status"] == "published" || e["status"] == "deprecated" || e["status"] == "superseded") ? e["released_at"] : "")
           geo_ids = [e["GSE"]]           
           geo_ids += e["GSM"] unless e["GSM"].nil?
           geo_ids += e["sra_ids"] unless e["sra_ids"].nil?
           cols.push geo_ids.compact.uniq.reject { |id| id.empty? }.sort.join(", ")
           extra_cols.values.each { |colname| cols.push e[colname] }
          
           if block_given? then
            yield cols
           else
            puts cols.join("\t")
          end
        end  #each file
      end #if files.nil?
    end #each exp
  end #def self.format_files

  def self.format_html(exps, filename = "output.html")
    filename = "output.html" if filename.nil?
    File.open(filename, "w") { |f|
      f.puts "<html>\n  <head>\n    <title>Exps</title>"
      f.puts <<-EOD
      <script src="http://submit.modencode.org/submit/javascripts/prototype.js" type="text/javascript"></script>
      <script type="text/javascript">
        var timer = setTimeout(function() { window.location.reload(); }, 10000);

        var rows = new Array();
        var title = new Array();
        var row_contents = new Array();
        var table;
        function enableSorting() {
          table = $(document.body).down().down();
          title = table.down().childElements(); //.map(function (n) { return n.innerHTML });
          rows = table.childElements().reject(function (n) { return n.down().tagName.toLowerCase() == "th" });

          row_contents = rows.map(function (n) { return n.childElements().map(function (nn) { return nn.innerHTML }) });

          title.each(function (n) {
              n.style.color = "blue";
              n.style.textDecoration = "underline";
              n.observe("click", function(event) { sortBy(n); });
              });
        }

        function sortBy(header) {
          clearTimeout(timer);
          var headerPos = title.indexOf(header);
          rows.each(function (n) { n.remove(); });
          new_rows = rows.sortBy(function (n) { 
              var row_content = n.childElements().map(function (nn) { return nn.innerHTML });
              var txt = row_content[headerPos];
              if (parseInt(txt) == txt) {
                return parseInt(txt);
              } else {
                return txt;
              }
              });
          rows = new_rows;
          color_mod = 0;
          colors = [ "#DDDDDD", "#DDDDFF" ];
          new_rows.each(function (n) {
            n.childElements().each(function(nn) { nn.style.backgroundColor = colors[(color_mod % 2)]; });
            color_mod++;
            table.insert(n);
            });

        }

      </script>
      EOD
      f.puts "  </head>"
      f.puts "<body onload=\"enableSorting()\">"

      f.puts "  <table>";
      header = true
      i = 0
      ignore_cols = {} #{ "Creation Date" => nil, "Release Date" => nil }
      colors = [ "#DDDDFF", "#DDDDDD" ]
      Formatter::format(exps) { |cols|
        f.puts "    <tr>"
        if header then
          ignore_cols.keys.each { |k| ignore_cols[k] = cols.find_index(k) }
          ignore_cols.values.compact.sort.reverse.each { |ignored_col_idx| cols.delete_at(ignored_col_idx) }
          f.puts cols.map { |c| "      <th style=\"border: thin solid black\">#{c}</th>" }.join("\n")
          header = false
        else
          i += 1
          color = colors[i%2]
          ignore_cols.values.compact.sort.reverse.each { |ignored_col_idx| cols.delete_at(ignored_col_idx) }
          f.puts cols.map { |c| "      <td style=\"background-color:#{color}\">#{c}</td>" }.join("\n")
        end
        f.puts "    </tr>"
      }
      f.puts "  </table>"
      f.puts "</body>"
      f.puts "</html>"
    }
  end
  def self.format_csv(exps, filename = "output.csv")
    filename = "output.csv" if filename.nil?
    File.open(filename, "w") { |f|
      Formatter::format(exps, false, {"Name" => "uniquename"}) { |cols|
        f.puts cols.join("\t")
      }
    }
  end
  def self.format_html_nih(exps, filename = "output_nih.html")
    filename = "output_nih.html" if filename.nil?
    File.open(filename, "w") { |f|
      header = true
      f.puts "<html>\n  <head>\n    <title>Exps</title>"
      f.puts "  </head>"
      f.puts "<body onload=\"enableSorting()\">"
      f.puts "  <table>";

      i = 0
      col_order = [
        "Description", "Project", "Lab", "Assay", "Data Type",
        "Experimental Factor", "Organism", "Cell Line", "Strain",
        "Tissue", "Stage/Treatment", "Date Data Submitted", "Release Date",
        "Status", "Submission ID", "GEO/SRA IDs"
      ]
      col_index = Hash.new
      colors = [ "#DDDDFF", "#DDDDDD" ]

      Formatter::format(exps, false, {"Description" => "uniquename", "Growth Condition" => "growth_condition", "DNAse Treatment" => "dnase_treatment", "Array Size" => "array_size", "Array Platform" => "array_platform", "Sequences" => "sequence_count", "Version" => "version", "Reactions" => "reactions", "Features" => "features" }) { |cols|
        f.puts "    <tr>"
        if header then
          cols.each_index { |idx| col_index[cols[idx]] = idx }
          f.puts col_order.map { |c|
            "      <th style=\"border: thin solid black\">#{c}</th>"
          }.join("\n")
          header = false
        else
          i += 1
          color = colors[i%2]
          line = Array.new
          col_order.each { |k|
            idx = col_index[k]
            cols[idx] = cols[idx].to_s.gsub(/N\/A/, "") unless (idx.nil? || cols[idx].nil?)
            if k == "Experimental Factor" then
              factors = Formatter::nih_factors(cols, col_index)
              line.push factors.map { |s| s.gsub(/, /, ",") }.join(";")
            elsif k == "Stage/Treatment" then
              line.push Formatter::slim_stages(cols[idx])
            elsif k == "Status" then
              line.push Formatter::nih_sub_status(cols[idx])
            elsif idx.nil? then
              puts "No column for #{k}"
              line.push ""
            else
              line.push cols[col_index[k]]
            end
          }
          f.puts line.map { |c| "      <td style=\"background-color:#{color}\">#{c}</td>" }.join("\n")
        end
        f.puts "    </tr>"
      }
    }
  end

  def self.nih_factors(cols, col_index)
    factors = Array.new              
    antibody = cols[col_index["Antibody Name"]].gsub(/N\/A/, "").gsub(/No Antibody Control/, "control")
    antibody = antibody.split(",")
    antibody.delete("control") if antibody.length > 1
    antibody = antibody.join(", ")
    target = cols[col_index["Target"]]
    factors.push "Target=#{target}" if target.length > 0
    factors.push "AbName=#{antibody}" if antibody.length > 0
    factors.push "SaltConcentration=#{cols[col_index["Compound"]].gsub(/sodium chloride/, "")}" if cols[col_index["Compound"]] =~ /sodium chloride/
    factors.push "RNAiTarget=#{cols[col_index["RNAi Target"]]}" if cols[col_index["RNAi Target"]].length > 0
    factors.push "EnvironmentalTreatment=#{cols[col_index["Growth Condition"]]}" if cols[col_index["Growth Condition"]].length > 0
    factors.push "DNAseTreatment=#{cols[col_index["DNAse Treatment"]]}" if cols[col_index["DNAse Treatment"]].length > 0
    factors.push "Array=#{cols[col_index["Array Size"]]}" if cols[col_index["Array Size"]].length > 1
    factors.push "ArrayPlatform=#{cols[col_index["Array Platform"]]}" if cols[col_index["Array Platform"]].length > 0
    factors.push "Sequences=#{cols[col_index["Sequences"]]}" if cols[col_index["Sequences"]] && cols[col_index["Sequences"]].to_i > 0
    factors.push "Version=#{cols[col_index["Version"]]}" if cols[col_index["Version"]] && cols[col_index["Version"]].to_i > 1
    factors.push "Reactions=#{cols[col_index["Reactions"]]}" if cols[col_index["Reactions"]] && cols[col_index["Reactions"]].to_i > 1
    factors.push "Features=#{cols[col_index["Features"]]}" if cols[col_index["Features"]] && cols[col_index["Features"]].to_i > 1
    factors.push "RNAsize=#{cols[col_index["RNAsize"]].join(",")}" if cols[col_index["RNAsize"]] && cols[col_index["RNAsize"]].length > 0
return factors
  end

  def self.nih_sub_status(s)            
    status_num = Project::Status::status_number(s)
    if !status_num.nil? then
      status = case Project::Status::status_number(s)
               when 0
                 "reviewing"
               when 1
                 "uploaded"
               when 2
                 "uploaded"                 
               when 3
                 "reviewing"
               when 4
                 "reviewing"
               when 5
                 "reviewing"
               when 6
                 "preview available"
               when 7
                 "approved"
               when 8
                 "released"
               when 9
                 "released"
               end                                      
    else       
      status = s
    end
    return status
  end

  def self.format_csv_nih(exps, filename = "output_nih.csv")
    filename = "output_nih.csv" if filename.nil?
    File.open(filename, "w") { |f|
      header = true

      i = 0
      col_order = [
        "Description", "Project", "Lab", "Assay", "Data Type", "Validation Dataset",
        "Experimental Factor", "Replicates", "Treatment", "Organism", "Cell Line",
        "Strain", "Tissue", "Stage/Treatment", "Date Data Submitted",
        "Release Date", "Status", "Submission ID", "GEO/SRA IDs", "GFF Files"
      ]
      col_index = Hash.new
      colors = [ "#DDDDFF", "#DDDDDD" ]

      Formatter::format(exps, false, {"Description" => "uniquename", "Replicates" => "replicates", "Growth Condition" => "growth_condition", "DNAse Treatment" => "dnase_treatment", "GFF Files" => "gff", "Array Size" => "array_size", "Array Platform" => "array_platform", "Sequences" => "sequence_count", "Version" => "version", "Reactions" => "reactions", "Features" => "features", "Validation Dataset" => "biological_validation", "RNAsize" => "rna_size" }) { |cols|
        if header then
          cols.each_index { |idx| col_index[cols[idx]] = idx }
          f.puts col_order.join("\t")
          header = false
        else
          i += 1
          color = colors[i%2]
          line = Array.new
          col_order.each { |k|
            idx = col_index[k]
            cols[idx] = cols[idx].to_s.gsub(/N\/A/, "") unless (idx.nil? || cols[idx].nil?)
            cols[idx] = cols[idx].to_s.gsub(/^\s*|\s*$/, "") unless (idx.nil? || cols[idx].nil?)
            if k == "Experimental Factor" then              
              factors = Formatter::nih_factors(cols, col_index)
              line.push factors.map { |s| s.gsub(/, /, ",") }.join(";")
            elsif k == "Replicates" then
              line.push cols[col_index["Replicates"]]
            elsif k == "Treatment" then
              treatments = Array.new
              treatments.push "RNAiTarget=#{cols[col_index["RNAi Target"]]}" if cols[col_index["RNAi Target"]].length > 0
              treatments.push "EnvironmentalTreatment=#{cols[col_index["Growth Condition"]]}" if cols[col_index["Growth Condition"]].length > 0
              line.push treatments.map { |s| s.gsub(/, /, ",") }.join(";")
            elsif k == "Cell Line" then
              #blank out the contents of stage, tissue, strain if cell line is present
              #TODO: add in logic to determine if its a copy number variation experiment, in which case leave them
               if !cols[idx].empty? then
                 cols[col_index["Stage/Treatment"]] = ""
                 cols[col_index["Tissue"]] = ""
                 cols[col_index["Strain"]] = ""
               end
               cell_lines = cols[idx]
               cell_lines = cell_lines.split(/, /)
               if cell_lines.length > 3 then
                 line.push "mixed"
               elsif cell_lines.length > 1 then
                 line.push "mixed: " + cell_lines.join(", ")
               else
                 line.push cell_lines.join(", ")
               end
            elsif k == "Stage/Treatment" then
              line.push Formatter::slim_stages(cols[idx]) 
            elsif k == "Status" then
              Formatter::nih_sub_status(cols[idx])
              status =  Formatter::nih_sub_status(cols[idx])
                if status =~ /deprecated|superseded/ then
                  status = "replaced"
                end
              line.push status
            elsif idx.nil? then
              puts "No column for '#{k}' in #{cols[col_index["Submission ID"]]}"
              line.push ""
            else
              line.push cols[col_index[k]]
            end
          }
          f.puts line.join("\t")
        end
      }
    }
  end

  def self.format_amazon_lite(exps, filename = "amazon_lite.csv")
    filename = "amazon_lite.csv" if filename.nil?
    File.open(filename, "w") { |f|
      header=true
      Formatter::format_files(exps, true, {}) { |cols|                  
        f.puts cols.join("\t")
      }
    }
  end

  def self.format_amazon_four_col(exps, filename = "amazon_four_col.csv")
    File.open(filename, "w") { |f|
      header = true
      col_order = ["Submission ID", "Title", "Data File", "Data Filepath", "Level 4 <File Format>", "GEO/SRA IDs", "Status"]
      col_index = Hash.new
      Formatter::format_files(exps, true, {}) { |cols|
        if header then #the header line only
          cols.each_index { |idx| col_index[cols[idx]] = idx}
          f.puts col_order.join("\t")
          header = false
        else #the content of the file
          line = Array.new
          col_order.each { |k|
            idx = col_index[k]
            cols[idx] = cols[idx].to_s.gsub(/N\/A/, "") unless (idx.nil? || cols[idx].nil?)
            cols[idx] = cols[idx].to_s.gsub(/^\s*|\s*$/, "") unless (idx.nil? || cols[idx].nil?)
          
            if idx.nil? then         
              line.push ""
            else
              line.push cols[col_index[k]]
            end
          }
          f.puts line.join("\t")
        end
      }
    }
  end

  def self.format_amazon_tagging(exps, filename = "amazon_tagging.csv")
    filename = "amazon_tagging.csv" if filename.nil?
    File.open(filename, "w") { |f|
      header = true
      i = 0
      col_order = ["DCC id", "Title", "Data File", "Data Filepath", "Level 1 <organism>", "Level 2 <Target>", "Level 3 <Technique>", "Level 4 <File Format>", "Filename <Factor>", "Filename <Condition>", "Filename <Technique>", "Filename <ReplicateSetNum>", "Filename <ChIP>", "Filename <label>", "Filename <Build>", "Filename <Modencode ID>", "Uniform filename", "Extensional Uniform filename", "factor", "Strain", "Cell Line", "Devstage", "Tissue", "other conditions", "PI"]
      col_index = Hash.new
      Formatter::format_files(exps, true, {"Title" => "uniquename", "Filename <Factor>" => "antibody_targets", "factor" => "antibody_targets", "Growth Condition" => "growth_condition" }) { |cols|
        if header then #the header line only
          cols.each_index { |idx| col_index[cols[idx]] = idx}
          f.puts col_order.join("\t")
          header = false
        else #the content of the file
          i += 1
          line = Array.new
          col_order.each { |k| 
            idx = col_index[k]
            cols[idx] = cols[idx].to_s.gsub(/N\/A/, "") unless (idx.nil? || cols[idx].nil?)
            cols[idx] = cols[idx].to_s.gsub(/^\s*|\s*$/, "") unless (idx.nil? || cols[idx].nil?)
            id = cols[col_index["Submission ID"]]
            if k == "DCC id" then
              line.push "#{id}"
            elsif k == "Filename <Modencode ID>" then
              line.push "modENCODE_#{id}"
            elsif k == "Level 1 <organism>" then
              line.push cols[col_index["Organism"]] unless (idx.nil? || cols[idx].nil?)
            elsif k == "Level 2 <Target>" then
              line.push cols[col_index["Data Type"]] unless (idx.nil? || cols[idx].nil?)
            elsif k == "Level 3 <Technique>" then
              line.push cols[col_index["Assay"]] unless (idx.nil? || cols[idx].nil?)
            #elsif k == "Filename <Factor>" then
            #  factor = "antibody_targets"
            #  if factor.empty? then
            #    factor = "NOT ANTIBODY BASED"
            #  end
            #  line.push factor
            #elsif k == ("Filename <Factor>" || "factor") then
            #  line.push cols[col_index["Experimental Factor"]]
            elsif k == "Filename <Condition>" then
              line.push Formatter::slim_stages(cols[col_index["Stage/Treatment"]]) unless (idx.nil? || cols[idx].nil?)
            elsif k ==  "Filename <Technique>" then
              line.push cols[col_index["Assay"]] unless (idx.nil? || cols[idx].nil?)
            elsif k == "Devstage" then
              line.push Formatter::slim_stages(cols[col_index["Stage/Treatment"]]) unless (idx.nil? || cols[idx].nil?)
            elsif k == "other conditions" then
              treatments = Array.new
              treatments.push "RNAiTarget_#{cols[col_index["RNAi Target"]]}" if cols[col_index["RNAi Target"]].length > 0 unless (idx.nil? || cols[idx].nil?)
              treatments.push "GrowthCondition_#{cols[col_index["Growth Condition"]]}" if cols[col_index["Growth Condition"]].length > 0 unless (idx.nil? || cols[idx].nil?)
              treatments.push "Compound_#{cols[col_index["Compound"]].gsub(/sodium chloride/, "NaCl")}" if !cols[col_index["Compound"]].empty?  unless (idx.nil? || cols[idx].nil?)
              treatments.push "Temperature_#{cols[col_index["Temp"]]}" if cols[col_index["Temp"]].length > 0 unless (idx.nil? || cols[idx].nil?)
              line.push treatments.map { |s| s.gsub(/, /, ",") }.join(";")

#              line.push (col_index["Treatment"].nil? ? "" : cols[col_index["Treatment"]])
            elsif k ==  "Cell Line" then
              l, cols = Formatter::cleanup_cell_line(cols[col_index["Cell Line"]], cols, col_index) unless (idx.nil? || cols[idx].nil?)
              line.push l.to_s 
            elsif k == "PI" then
              line.push cols[col_index["Project"]] unless (idx.nil? || cols[idx].nil?)
            elsif ["Filename <ReplicateSetNum>","Filename <ChIP>", "Filename <label>","Filename <Build>","Uniform filename","Extensional Uniform filename"].include?(k) then
              line.push "*"
            elsif idx.nil? then
              line.push ""
            else
              line.push cols[col_index[k]]
            end
          }
          f.puts line.join("\t")
        end
      }
    }
  end

  def self.slim_stages (stage_list)     
    stage = stage_list
    stage = stage.split(/, /).reject { |s| s =~ /Embryo \d+-\d+ h/ }.join(", ")
    if stage =~ /embryonic stage \d+/ then
        stages = stage.split(/, /)
        stages.sort! { |a, b|
          a1 = a.match(/ (\d+)$/)
          a1 = a1.nil? ? a : a1[1]
          b1 = b.match(/ (\d+)$/)
          b1 = b1.nil? ? b : b1[1]
          if a1.to_i.to_s == a1 && b1.to_i.to_s == b1 then
            a1 = a1.to_i; b1 = b1.to_i
          end
          a1 <=> b1
        }
        min = -10; max = -10
        prev = -10
        blocks = Array.new
        stages.each { |stg|
          val = stg.match(/ (\d+)$/)
          if val then
            val = val[1].to_i
            if prev+1 < val then # New block of nums
              blocks.push(min == max ? "embryonic stage #{min}" : "embryonic stage #{min}-#{max}") if min > 0
              min = max = prev = val
            else
              max = prev = val
            end
          else
            blocks.push stg
          end
        }
        blocks.push(min == max ? "embryonic stage #{min}" : "embryonic stage #{min}-#{max}") if min > 0
        stage = blocks.join(", ")
      end
      if ((stage =~ /embryo|cleavage|blastoderm|gastrula|germ band|egg/) && (stage =~ /larva|(L\d+)|prepupa|dauer|pupa|P[3-9]|adult/)) then
        stage = "mixed: " + stage
      elsif stage =~ /embryo|cleavage|blastoderm|gastrula|germ band|egg/ then
        stage = "embryo: " + stage
      elsif stage =~ /larva(l)?|L\d stage|prepupa|dauer|molt/ then
        stage = "larva: " + stage
      elsif stage =~ /pupa|P([3-9]|1[1-4])|pharate adult/ then
        stage = "pupae: " + stage
      elsif stage =~ /adult/ then
        stage = "adult: " + stage
      end
    return stage
  end

  def self.cleanup_cell_line (cell_lines, cols, col_index)
    line = Array.new

    if !cell_lines.empty? then
      cols[col_index["Stage/Treatment"]] = ""
      cols[col_index["Tissue"]] = ""
      cols[col_index["Strain"]] = ""
    end
    cell_lines = cell_lines.split(/, /)
    if cell_lines.length > 3 then
      line.push "mixed"
    elsif cell_lines.length > 1 then
      line.push "mixed: " + cell_lines.join(", ")
    else
      line.push cell_lines.join(", ")
    end

    return line, cols
  end

end
