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
      <script type="text/javascript">
        setTimeout(function() { window.location.reload(); }, 10000);
      </script>
      EOD
      f.puts "  </head>"
      f.puts "<body>"

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