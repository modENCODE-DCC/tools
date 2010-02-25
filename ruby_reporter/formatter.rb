require 'rubygems'
require '/var/www/pipeline/submit/config/environment'
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
        "Antibody",
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
      cols.push e["antibody_names"].join(", ")
      cols.push e["compound"].join(", ")
      cols.push e["array_platform"].join(", ")
      cols.push e["rnai_targets"].join(", ")
      cols.push e["created_at"]
      cols.push e["released_at"]
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

      Formatter::format(exps, false, {"Description" => "uniquename", "Growth Condition" => "growth_condition", "DNAse Treatment" => "dnase_treatment"}) { |cols|
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
              antibody = cols[col_index["Antibody"]].gsub(/N\/A/, "").gsub(/No Antibody Control/, "control")
              factors.push "AbName=#{antibody}" if antibody.length > 0
              factors.push "RNAiTarget=#{cols[col_index["RNAi Target"]]}" if cols[col_index["RNAi Target"]].length > 0
              factors.push "SaltConcentration=#{cols[col_index["Compound"]].gsub(/sodium chloride/, "")}" if cols[col_index["Compound"]] =~ /sodium chloride/
              factors.push "EnvironmentalTreatment=#{cols[col_index["Growth Condition"]]}" if cols[col_index["Growth Condition"]].length > 0
              factors.push "DNAseTreatment=#{cols[col_index["DNAse Treatment"]]}" if cols[col_index["DNAse Treatment"]].length > 0
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
        "Description", "Project", "Lab", "Assay", "Data Type",
        "Experimental Factor", "Organism", "Cell Line", "Strain",
        "Tissue", "Stage/Treatment", "Date Data Submitted", "Release Date",
        "Status", "Submission ID", "GEO/SRA IDs", "GFF Files"
      ]
      col_index = Hash.new
      colors = [ "#DDDDFF", "#DDDDDD" ]

      Formatter::format(exps, false, {"Description" => "uniquename", "Growth Condition" => "growth_condition", "DNAse Treatment" => "dnase_treatment", "GFF Files" => "gff"}) { |cols|
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
              antibody = cols[col_index["Antibody"]].gsub(/N\/A/, "").gsub(/No Antibody Control/, "control")
              factors.push "AbName=#{antibody}" if antibody.length > 0
              factors.push "RNAiTarget=#{cols[col_index["RNAi Target"]]}" if cols[col_index["RNAi Target"]].length > 0
              factors.push "SaltConcentration=#{cols[col_index["Compound"]].gsub(/sodium chloride/, "")}" if cols[col_index["Compound"]] =~ /sodium chloride/
              factors.push "EnvironmentalTreatment=#{cols[col_index["Growth Condition"]]}" if cols[col_index["Growth Condition"]].length > 0
              factors.push "DNAseTreatment=#{cols[col_index["DNAse Treatment"]]}" if cols[col_index["DNAse Treatment"]].length > 0
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
                status = case status_num
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
              status = cols[idx]
              line.push status
            elsif idx.nil? then
              puts "No column for #{k}"
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
