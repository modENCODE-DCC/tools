#!/usr/bin/ruby

require 'pp'
require 'rubygems'
require 'dbi'
require 'base64'

# USAGE:
# ./gffify.sh <CSV of exp info>       <source gffs>  <dest dir>
# ./gffify.sh celegans_2010-02-15.csv celegans_gffs/ /local/fbwb/celegans/

exps = Array.new

if ARGV[0].nil?
  puts "You need to provide a CSV"
  exit
end

exp_info = Hash.new

if (File.exist?("collected_experiment_info_#{File.basename(ARGV[0], ".csv")}.dmp")) then
  File.open("collected_experiment_info_#{File.basename(ARGV[0], ".csv")}.dmp", "r") { |f| exp_info = Marshal.load(f) }
else
  File.open(ARGV[0]) do |f|

    puts "Connecting to DB"
    @db = DBI.connect("DBI:Pg:dbname=modencode_chado;host=awol.lbl.gov;port=5433", "db_public", "ir84#4nm")
    @db_pipeline = DBI.connect("DBI:Pg:dbname=pipeline_dev;host=awol.lbl.gov;port=5433", "db_public", "ir84#4nm");
    puts "Done."

    @sth_citation = @db_pipeline.prepare("SELECT marshaled_stanza FROM track_stanzas WHERE project_id = ?")

    header = f.gets.chomp.split(/\t/)
    while (line = f.gets) do
      row = line.chomp.split(/\t/, -1)
      e = Hash.new
      row.each_index { |i| e[header[i]] = row[i] }
      @sth_citation.execute(e["Submission ID"].to_i)
      row = @sth_citation.fetch
      if row.nil? then
        e["Citation"] = "---------CITATION NEEDED---------"
      else
        e["Citation"] = Marshal.restore(Base64.decode64(row[0])).values.first["citation"]
      end
      # Any regulome with H#K# is actually chromatin modification
      e["Antibody"] = "No Antibody Control" if e["Antibody"] == "na"
      e["Antibody"] = e["Antibody"].split(/, /).uniq.join(", ")
      antibodies = e["Antibody"].split(/, /)
      if antibodies.find { |a| a =~ /fly_genes:/ } then
        sth = @db.prepare("SELECT a1.value FROM modencode_experiment_#{e["Submission ID"]}_data.attribute a1 
                            INNER JOIN modencode_experiment_#{e["Submission ID"]}_data.data_attribute da1 ON a1.attribute_id = da1.attribute_id
                            INNER JOIN modencode_experiment_#{e["Submission ID"]}_data.data_attribute da2 ON da1.data_id = da2.data_id
                            INNER JOIN modencode_experiment_#{e["Submission ID"]}_data.attribute a2 ON da2.attribute_id = a2.attribute_id
                            WHERE a1.heading = 'target name' AND a2.value = ?")
        antibodies.find_all { |a| a =~ /fly_genes:/ }.each { |a|
          sth.execute(a)
          target = sth.fetch[0]
          a.replace(target) unless target.nil?
        }
        e["Antibody"] = antibodies.join(", ")
      end
      antibodies = e["Antibody"].split(/, /).uniq
      if antibodies.find { |a| a =~ /worm_genes:/ } then
        e["Antibody"] = antibodies.map { |a| a.sub(/worm_genes:/, '') }.join(", ")
      end
      if e["Antibody"] =~ /(?:^|[Hh]istone )H\d+(([A-Z]\d.*|[Tt]etra)([Mm][Ee]|[Aa][Cc]|[Bb]ubi))?/
        puts "Modification site change because antibody is #{e["Antibody"]}"
        if e["Antibody"] =~ /[tT]rimethylated Lys-(\d+) o[fn] histone (H\d+)/ then
          m = e["Antibody"].match(/[tT]rimethylated Lys-(\d+) o[fn] histone (H\d+)/)
          e["Antibody"] = "#{m[2]}K#{m[1]}Me3"
        end
        e["Antibody"] = e["Antibody"].match(/(?:^|[Hh]istone )(H\d+(([A-Z]\d+|[Tt]etra|[Bb])?([Mm][Ee]|[Aa][Cc]|[Uu]bi)(\d+)?)?)([Tt]etra)?/)[1]
        e["Antibody"].sub!(/[Aa][Cc](\d)?/, 'Ac\1')
        e["Antibody"].sub!(/[Mm][Ee](\d)?/, 'Me\1')
        e["Antibody"].sub!(/[Bb]ubi/, 'BUbi')
        e["Antibody"].sub!(/tetra/, 'Tetra')
        puts "  Cleaned antibody to #{e["Antibody"]}"
        e["Data Type"].sub!(/chromatin binding site signal data/, "chromatin modification binding site signal data")
      end
      exps.push e if e["GFF Files"]
    end
  end


  # REGULOME
  regulome_exps = exps.find_all { |e| e["Data Type"].split(/, /).include?("chromatin binding site signal data") }
  exps -= regulome_exps

  # CHROMATIN
  chromatin_exps = exps.find_all { |e| 
    data_types = e["Data Type"].split(/, /)
    data_types.include?("chromatin modification binding site signal data") || 
    data_types.include?("origins of replication") || 
    data_types.include?("replication timing") || 
    e["Compound"] =~ /sodium chloride/ 
  }
  exps -= chromatin_exps

  # TRANSCRIPTOME
  transcriptome_exps = exps

  exp_info = {
    :transcriptome => transcriptome_exps,
    :regulome => regulome_exps,
    :chromatin => chromatin_exps
  }
  File.open("collected_experiment_info_#{File.basename(ARGV[0], ".csv")}.dmp", "w") { |f| Marshal.dump(exp_info, f) }
end


fly_stages = Hash.new
File.open("fly_times.txt", "r") { |f| f.each { |line| x = line.chomp.split(/: /, 2); fly_stages[x[0]] = x[1].sub(/ minutes/, "").split(/-/, 2).map { |n| n.to_i } } }
worm_stages = Hash.new
File.open("worm_times.txt", "r") { |f| f.each { |line| x = line.chomp.split(/: /, 2); worm_stages[x[0]] = x[1].sub(/ minutes after.*/, "").split(/-/, 2).map { |n| n.to_i } } }

copies = Array.new
not_found = Array.new
readmes_by_dir = Hash.new { |h, k| h[k] = Hash.new }

exp_info.each { |category, exps|
  exps.each { |e|
    strain = e["Strain"].split(/, /).reject { |x| x.empty? || x == "N/A" }.map { |x| x.gsub(/[^a-zA-Z0-9]/, "_") }
    cell_line = e["Cell Line"].split(/, /).reject { |x| x.empty? }.map { |x| x.gsub(/[^a-zA-Z0-9]/, "_") }
    tissue = e["Tissue"].split(/, /).reject { |x| x.empty? }.map { |x| x.gsub(/[^a-zA-Z0-9]/, "_") }
    stage = e["Stage/Treatment"].split(/, /).reject { |x| x.empty? }
    sid = e["Submission ID"]

    tissue.delete_if { |x| x == "whole_organism" }

    # Transform stages
    if e["Organism"] == "Caenorhabditis elegans" then
      stage = ["All Stages"] if stage.include?("all stages")
      stage = ["All Stages"] if (stage & [ "adult", "embryo", "larva" ]).size == 3
      stage = ["All Stages"] if (stage & [ "adult", "embryo", "L1 larva" ]).size == 3

      embryonic_stages = stage.find_all { |x| x =~ / embryo/ }
      unless embryonic_stages.nil? || embryonic_stages.size == 0 then
        found_stages = embryonic_stages.find_all { |x| worm_stages[x] }
        if found_stages.size > 0 then
          early = found_stages.map { |x| worm_stages[x][0] }.min
          late = found_stages.map { |x| worm_stages[x][1] }.max
          suffix = "m"
          if late > 60 then
            early = (early.to_f / 60).ceil
            late = (late.to_f / 60).floor
            late += 1 if (late % 2 != 0)
            early -= 1 if (early % 2 != 0)
            suffix="h"
          end
          stage -= found_stages
          stage.push "Embryo #{early}-#{late}#{suffix}"
        end
      end

      if stage.include?("1-cell embryo") then
        stage -= [ "1-cell embryo" ]
        stage += [ "Zygote" ]
      end
      stage -= ["L4-adult molt"]

      stage.each { |x| x.gsub!(/\b\w/){ |w| w.upcase } }

    elsif e["Organism"] =~ /^Drosophila / then

      if stage.include?("all stages") || (stage & ["adult stage", "embryonic stage", "pupal stage", "larval stage"]).size == 4 then
        stage = ["All Stages"]
      end

      if stage.find { |x| x =~ /embryonic stage \d/ }.nil? then
        stage += [ "embryonic stage 16", "embryonic stage 17" ] if stage.include?("late embryonic stage")
        stage += [ "embryonic stage 1", "embryonic stage 2", "embryonic stage 3", "embryonic stage 4" ] if stage.include?("cleavage stage")
        stage += [ "embryonic stage 1", "embryonic stage 2", "embryonic stage 3" ] if stage.include?("pre-blastoderm stage")
        stage += [ "embryonic stage 9", "embryonic stage 10", "embryonic stage 11", "embryonic stage 12" ] if stage.include?("extended germ band stage")
        stage += [ "embryonic stage 6", "embryonic stage 7", "embryonic stage 8" ] if stage.include?("gastrula stage")
        stage += [ "embryonic stage 13", "embryonic stage 14", "embryonic stage 15" ] if stage.include?("dorsal closure stage")
      end

      embryonic_stages = stage.find_all { |x| x =~ /^embryonic stage / }
      unless embryonic_stages.nil? || embryonic_stages.size == 0 then
        early = embryonic_stages.map { |x| fly_stages[x][0] }.min
        late = embryonic_stages.map { |x| fly_stages[x][1] }.max
        early = (early.to_f / 60).ceil
        late = (late.to_f / 60).floor
        late += 1 if (late % 2 != 0)
        early -= 1 if (early % 2 != 0)
        stage -= embryonic_stages
        stage -= ["embryonic stage", "late embryonic stage", "pre-blastoderm stage", "early extended germ band stage", "cleavage stage", "extended germ band stage", "late extended germ band stage", "late embryonic stage", "dorsal closure stage", "gastrula stage" ]
        stage.push "Embryo #{early}-#{late}h"
      end
      stage = stage - embryonic_stages

      pupal_stages = stage.find_all { |x| x =~ /(pharate adult|pupal) stage P/ }
      unless pupal_stages.nil? || pupal_stages.size == 0 then
        early = pupal_stages.map { |x| fly_stages[x][0] }.min
        late = pupal_stages.map { |x| fly_stages[x][1] }.max
        s = (late <= 7932) ? "Prepupa" : "Pupa"
        early = (early.to_f / 60).ceil
        late = (late.to_f / 60).floor
        if (late > 24 && early > 24) then
          late /= 24
          early /= 24
#          late += 1 if (late % 2 != 0)
#          early -= 1 if (early % 2 != 0)
          s += " #{early}"
          s += "-#{late}" if late != early 
          stage.push "#{s}days"
        else
          late += 1 if (late % 2 != 0)
          early -= 1 if (early % 2 != 0)
          s += " #{early}"
          s += "-#{late}" if late != early 
          stage.push "#{s}h"
        end
        stage -= pupal_stages
        stage -= ["pupal stage", "pharate adult stage", "prepupal stage"]
      end
      stage = stage - pupal_stages

      egg_stages = stage.find_all { |x| x =~ /(^| )egg / }
      stage = stage - egg_stages
      stage.push "Egg" if egg_stages.size > 0

      if stage.find { |x| x =~ /instar larval stage$/ } then
        stage -= ["larval stage"]
      end
      if stage.include?("first instar larval stage") then
        stage -= [ "first instar larval stage" ]
        stage = [ "First Instar" ]
      end
      if stage.include?("second instar larval stage") then
        stage -= [ "second instar larval stage" ]
        stage = [ "Second Instar" ]
      end
      if stage.include?("third instar larval stage") then
        stage -= [ "third instar larval stage" ]
        stage = [ "Third Instar" ]
      end
      stage = [ "Embryo" ] if stage == [ "embryonic stage" ]
      stage = [ "Pupa" ] if stage == [ "pupal stage" ]
      stage = [ "Larva" ] if stage == [ "larval stage" ]
      if stage.include?("adult stage") then
        stage -= [ "adult stage" ]
        stage += [ "Adult" ]
      end
    else
      puts "Dunno what to do for stages with organism #{e["Organism"]}"
      exit
    end
    stage = stage.map { |x| x.gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, "") }
    stage -= [ "Egg" ] if stage.size > 1
    e["Stage/Treatment"] = stage.join(", ")

    organism = e["Organism"].split(" ")[0][0..0] + e["Organism"].split(" ")[1][0..2].upcase

    if e["Antibody"] =~ /.*GFP/ then
      e["Antibody"] = e["Strain"]
    end
    e["Antibody"] = (e["Antibody"].split(/, /) - [ "No Antibody Control" ]).join(", ") if e["Antibody"] =~ /,/
    antibodies = e["Antibody"].split(/, /)


    filename = "#{organism}_#{category.to_s.upcase}"
    filename += "_STRAIN_#{strain.join("__")}" if strain.size > 0 
    filename += "_CELL_LINE_#{cell_line.join("__")}" if cell_line.size > 0 
    if cell_line.size <= 0 then
      filename += "_TISSUE_#{tissue.join("__")}" if tissue.size > 0 
      filename += "_STAGE_#{stage.join("__")}" if stage.size > 0 
    end
    filename += "_TARGET_#{antibodies.map { |x| x.gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, "") }.join("__")}" if antibodies.size > 0 

    condition = stage.join("__") if stage.size > 0
    condition = tissue.join("__") if tissue.size > 0
    condition = cell_line.join("__") if cell_line.size > 0
    condition = "Computational_Results" if e["Assay"] == "Computational annotation"
    puts "No condition for #{e.pretty_inspect}" if condition.nil?

    # TODO: Figure out binding protein or mod type
    dirname = case category
    when :transcriptome then
      if e["Data Type"] =~ /copy number variation/ then
        filename.sub!(/TRANSCRIPTOME/, "TRANSCRIPTOME_CNV")
        File.join("Transcriptome", "Copy_Number_Variation", condition)
      else
        File.join("Transcriptome", condition)
      end
    when :regulome then
      antibodies = e["Antibody"].split(/, /)
      File.join("Regulome", antibodies.map { |x| x.gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, "") }.join("__"), condition)
    when :chromatin then
      antibodies = e["Antibody"].split(/, /)
      if antibodies.size == 0 && e["Compound"] =~ /sodium chloride/ then
        antibodies = [ e["Compound"] ]
        filename += "_TREATMENT_#{e["Compound"].gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, "")}"
      end
      if e["Data Type"] == "replication timing" then
        filename.sub!(/CHROMATIN/, "CHROMATIN_REPTIMING")
        File.join("Chromatin", "Replication_Timing", condition)
      elsif e["Data Type"] =~ /origins of replication/ then
        filename.sub!(/CHROMATIN/, "CHROMATIN_ORI")
        File.join("Chromatin", "Origins_of_Replication", condition)
      else
        File.join("Chromatin", antibodies.map { |x| x.gsub(/[^a-zA-Z0-9-]/, "_").sub(/_*$/, "") }.join("__"), condition)
      end
    end

    next if e["Data Type"] =~ /metadata only/
    filename += "_SID_#{e["Submission ID"]}"
    if ARGV[1].nil? then
      puts "You need to provide a directory to copy from."
      exit
    end
    if !File.directory?(ARGV[1]) then
      puts "Can't copy files from #{ARGV[1]}"
      exit
    end
    if ARGV[2].nil? then
      puts "You need to provide a directory to copy to."
      exit
    end
    if !File.directory?(ARGV[2]) then
      puts "Can't copy files to #{ARGV[2]}"
      exit
    end
    e["GFF Files"].split(/, /).each { |gff_file|
      filename_gff = filename + "_#{File.basename(gff_file).sub(/\.[^.]+$/, '')}.gff"
      src_file = File.join(ARGV[1], e["Submission ID"], "extracted", gff_file)
      if !File.exist?(src_file) then
        base = File.join(ARGV[1], e["Submission ID"], "extracted")
        if !File.directory?(base) then
          puts "Cannot find directory #{base}"
          not_found.push src_file
          next
        end
        subdir = Dir.entries(base).reject { |d| d =~ /^\.|WS\d+/i }
        if subdir.size == 1 then
          new_src_file = File.join(base, subdir[0], gff_file)
          if File.exists?(new_src_file) then
            src_file = new_src_file
          else
            not_found.push src_file
            puts "Not found: #{src_file}"
          end
        else
          not_found.push src_file
          puts "Not found: #{src_file}"
        end
      end
      dest_file = File.join(ARGV[2], dirname, filename_gff)

      readmes_by_dir[File.dirname(dest_file)][e["Submission ID"]] = e["Citation"]
      copies.push [src_file, dest_file]
    }



  }
}

if not_found.size == 0 then
  copies.each { |copy|
    puts "Copying #{copy[0]} to #{copy[1]}"
    dir = File.dirname(copy[1])
    if (!File.directory?(dir)) then
      FileUtils.mkdir_p(File.dirname(copy[1]))
      readmes = "<html><head><title>Readmes for #{dir}</title></head><body>\n" + readmes_by_dir[dir].map { |sid, citation| "<h1>SID #{sid}</h1>\n<blockquote>#{citation}</blockquote>" }.join("<br/>\n") + "\n</body></html>"
      File.open(File.join(dir, "README.html"), "w") { |f| f.puts readmes }
    end
    FileUtils.cp(copy[0], copy[1])
  }
end


