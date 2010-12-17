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
      cols.push e["array_platform"].join(", ")
      cols.push e["rnai_targets"].join(", ")
      cols.push e["created_at"]
      cols.push((e["status"] == "released" || e["status"] == "published" || e["status"] == "deprecated" || e["status"] == "superseded") ? e["released_at"] : "")
      geo_ids = [e["GSE"]]
      geo_ids += e["GSM"] unless e["GSM"].nil?
      geo_ids += e["sra_ids"] unless e["sra_ids"].nil?
      cols.push geo_ids.compact.sort.join(", ")
      extra_cols.values.each { |colname| cols.push e[colname] }

      if block_given? then
        yield cols
      else
        puts cols.join("\t")
      end
    end
  end
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
              factors = Array.new
              antibody = cols[col_index["Antibody Name"]].gsub(/N\/A|^na$/i, "").gsub(/No Antibody Control/, "control")
              factors.push "AbName=#{antibody}" if antibody.length > 0
              factors.push "SaltConcentration=#{cols[col_index["Compound"]].gsub(/sodium chloride/, "")}" if cols[col_index["Compound"]] =~ /sodium chloride/
              factors.push "RNAiTarget=#{cols[col_index["RNAi Target"]]}" if cols[col_index["RNAi Target"]].length > 0
              factors.push "EnvironmentalTreatment=#{cols[col_index["Growth Condition"]]}" if cols[col_index["Growth Condition"]].length > 0
              factors.push "DNAseTreatment=#{cols[col_index["DNAse Treatment"]]}" if cols[col_index["DNAse Treatment"]].length > 0
              factors.push "Array=#{cols[col_index["Array Size"]]}" if cols[col_index["Array Size"]].length > 0
              factors.push "ArrayPlatform=#{cols[col_index["Array Platform"]]}" if cols[col_index["Array Platform"]].length > 0
              factors.push "Sequences=#{cols[col_index["Sequences"]]}" if cols[col_index["Sequences"]] && cols[col_index["Sequences"]].to_i > 0
              factors.push "Version=#{cols[col_index["Version"]]}" if cols[col_index["Version"]] && cols[col_index["Version"]].to_i > 1
              factors.push "Reactions=#{cols[col_index["Reactions"]]}" if cols[col_index["Reactions"]] && cols[col_index["Reactions"]].to_i > 1
              factors.push "Features=#{cols[col_index["Features"]]}" if cols[col_index["Features"]] && cols[col_index["Features"]].to_i > 1
              line.push factors.map { |s| s.gsub(/, /, ",") }.join(";")
            elsif k == "Stage/Treatment" then
              stage = cols[idx]
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
              line.push stage
            elsif k == "Status" then
              status_num = Project::Status::status_number(cols[idx])
              if !status_num.nil? then
                status = case Project::Status::status_number(cols[idx])
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
                status = cols[idx]
              end
              line.push status
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
              factors = Array.new
              antibody = cols[col_index["Antibody Name"]].gsub(/N\/A/, "").gsub(/No Antibody Control/, "control")
              antibody = antibody.split(",")
              antibody.delete("control") if antibody.length > 1
              antibody = antibody.join(", ")
              target = cols[col_index["Target"]]
              factors.push "Target=#{target}" if target.length > 0
              factors.push "AbName=#{antibody}" if antibody.length > 0
              factors.push "SaltConcentration=#{cols[col_index["Compound"]].gsub(/sodium chloride/, "")}" if cols[col_index["Compound"]] =~ /sodium chloride/
              factors.push "DNAseTreatment=#{cols[col_index["DNAse Treatment"]]}" if cols[col_index["DNAse Treatment"]].length > 0
              factors.push "Array=#{cols[col_index["Array Size"]]}" if cols[col_index["Array Size"]].length > 0
              factors.push "ArrayPlatform=#{cols[col_index["Array Platform"]]}" if cols[col_index["Array Platform"]].length > 0
              factors.push "Sequences=#{cols[col_index["Sequences"]]}" if cols[col_index["Sequences"]] && cols[col_index["Sequences"]].to_i > 0
              factors.push "Version=#{cols[col_index["Version"]]}" if cols[col_index["Version"]] && cols[col_index["Version"]].to_i > 1
              factors.push "Reactions=#{cols[col_index["Reactions"]]}" if cols[col_index["Reactions"]] && cols[col_index["Reactions"]].to_i > 1
              factors.push "Features=#{cols[col_index["Features"]]}" if cols[col_index["Features"]] && cols[col_index["Features"]].to_i > 1
              factors.push "RNAsize=#{cols[col_index["RNAsize"]].join(",")}" if cols[col_index["RNAsize"]] && cols[col_index["RNAsize"]].length > 0
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
              stage = cols[idx]
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

              line.push stage
            elsif k == "Status" then
              status_num = Project::Status::status_number(cols[idx])
              #TODO: add in displayed - gbrowse, and released should be availability in modmine
              if !status_num.nil? then
                status = case status_num
                         when 0 # usually means queued
                           "reviewing"
                         when 1 #new
                           "uploaded"
                         when 2 #uploaded
                           "uploaded"
                         when 3 #expanded
                           "uploaded"
                         when 4 #validated
                           "reviewing"
                         when 5 #loaded
                           "reviewing"
                         when 6 #tracks found
                           "reviewing"
                         when 7 #tracks approved
                           "approved"
                         when 8 #released
                           "released"
                         when 9 #???
                           "released"
                         end
                #TODO: add in an item for retracted
              else
                status = cols[idx]
                if status =~ /deprecated|superseded/ then
                  status = "replaced"
                end
              end
              #status = cols[idx]
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
end
