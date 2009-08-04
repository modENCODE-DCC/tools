class Formatter
  def self.format(exps)
    cols = [
        "ID",
        "Project",
        "Lab",
        "Organism",
        "Data Type",
        "Experiment Type",
        "Tissue",
        "Strain",
        "Cell Line",
        "Stage",
        "Antibody",
        "Creation Date",
        "Release Date",
        "GEO IDs",
    ]
    if block_given? then
      yield cols
    else
      puts cols.join("\t")
    end
    exps.each do |e|
      cols = Array.new
      cols.push e["xschema"].match(/_(\d+)_/)[1]
      cols.push e["project"]
      cols.push e["lab"]
      cols.push e["organisms"].map { |o| "#{o["genus"]} #{o["species"]}" }.join(", ")
      cols.push e["types"].join(", ")
      cols.push e["experiment_types"].join(", ")
      cols.push e["tissue"].join(", ")
      cols.push e["strain"].map { |s| 
        s == "y[1]; Gr22b[1] Gr22d[1] cn[1] CG33964[R4.2] bw[1] sp[1]; LysC[1] MstProx[1] GstD5[1] Rh6[1]" ? "y; cn bw sp" : s 
      }.map { |s| 
        s =~ /y\[1\].*\scn\[1\].*\sbw\[1\].*\ssp\[1\]/ ? "y; cn bw sp" : s 
      }.uniq.sort.join(", ")
      cols.push e["cell_line"].uniq.join(", ")
      cols.push e["stage"].size > 5 ? e["stage"].sort[0..5].join(", ") + ", and #{e["stage"].size-5} more..." : e["stage"].sort.join(", ")
      cols.push e["antibody_names"].join(", ")
      cols.push e["created_at"]
      cols.push e["released_at"]
      geo_ids = [e["GSE"]]
      geo_ids += e["GSM"] unless e["GSM"].nil?
      cols.push geo_ids.compact.sort.join(", ")

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
      ignore_cols = { "Creation Date" => nil, "Release Date" => nil }
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
      Formatter::format(exps) { |cols|
        f.puts cols.join("\t")
      }
    }
  end
end
