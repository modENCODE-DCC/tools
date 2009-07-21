#!/usr/bin/ruby

require 'rubygems'
require 'cgi'
require 'dbi'
require 'pp'
require '/var/www/pipeline/submit/lib/pg_database_patch'
require 'formatter'
require 'chado_reporter'

module Enumerable
  def uniq_by
    h = {}; inject([]) { |a,x| h[yield(x)] ||= a << x }
  end
end


r = ChadoReporter.new
r.set_schema("reporting")

if (File.exists?('breakpoint4.dmp')) then
  exps = Marshal.load(File.read('breakpoint4.dmp'))
else
  if (File.exists?('breakpoint3.dmp')) then
    exps = Marshal.load(File.read('breakpoint3.dmp'))
  else
    if (File.exists?('breakpoint2.dmp')) then
      exps = Marshal.load(File.read('breakpoint2.dmp'))
    else
      if (File.exists?('breakpoint1.dmp')) then
        exps = Marshal.load(File.read('breakpoint1.dmp'))
      else
        r.init_reporting_function
        r.make_reporting_views(false)
        exps = r.get_available_experiments.map { |exp| exp.to_h }
        exps.each do |experiment|
          print "."
          $stdout.flush
          experiment["types"] = r.get_feature_types(experiment["xschema"])
        end
        print "\n"
        File.open('breakpoint1.dmp', 'w') { |f| Marshal.dump(exps, f) }
      end

      # TODO: Remove debugging removal of experiments
      exps.delete_if { |e|
        # Bad schemas
        e["xschema"] =~ /^modencode_experiment_(0)_data$/ #||
        # Signal data only
        # TODO: Deal with signal data
#        e["xschema"] =~ /^modencode_experiment_(168|175|176|179|188|194|350|351|352|441|442|443|444|202)_data$/
      }

        # TODO: Tack the word "alignments" after ESTs and cDNA
      exps.each { |e| 
        types = e["types"] 
        nice_types = Array.new

        found_types = types.find_all { |type|
          type =~ /^(intron|exon)(_.*)?$/ ||
          type =~ /^(start|stop)_codon$/
        }
        if found_types.size > 0 then
          nice_types.push "splice sites"
          types -= found_types
        end

        found_types = types.find_all { |type|
          type =~ /CDS|UTR/ ||
          type =~ /^TSS$/ ||
          type =~ /^transcription_end_site$/
        }
        if found_types.size > 0 then
          nice_types.push "transcription/coding junctions"
          types -= found_types
        end

        found_types = types.find_all { |type| type =~ /(.*_)?match(_.*)?/ }
        if found_types.size > 0 then
          nice_types.push "alignments"
          types -= found_types
        end

        found_types = types.find_all { |type| type =~ /^TraceArchive_record$/ }
        if found_types.size > 0 then
          nice_types.push "trace reads"
          types -= found_types
        end

        found_types = types.find_all { |type|
          type =~ /^(gene|transcript_region|transcript|mRNA)$/
        }
        if found_types.size > 0 then
          nice_types.push "gene models"
          types -= found_types
        end

        found_types = types.find_all { |type|
          type =~ /^(.*_)?binding_site$/
        }
        if found_types.size > 0 then
          nice_types.push "binding sites"
          types -= found_types
        end

        found_types = types.find_all { |type| type =~ /^origin_of_replication$/ }
        if found_types.size > 0 then
          nice_types.push "origins of replication"
          types -= found_types
        end

        found_types = types.find_all { |type| type =~ /^copy_number_variation$/ }
        if found_types.size > 0 then
          nice_types.push "copy number variation"
          types -= found_types
        end

        found_types = types.find_all { |type|
          type =~ /^(EST|overlapping_EST_set)$/
        }
        if found_types.size > 0 then
          nice_types.push "EST alignments"
          types -= found_types
        end

        found_types = types.find_all { |type|
          type =~ /^(chromosome(_.*)?)$/ ||
          type =~ /^region$/
        }
        types -= found_types

        found_types = types.find_all { |type|
          type =~ /cDNA/
        }
        if found_types.size > 0 then
          nice_types.push "cDNA alignments"
          types -= found_types
        end

        nice_types += types
        if nice_types.size == 0 then
          # No feature data!?
          puts "No feature data for experiment #{e["xschema"]}"
          # Still might be BAM or WIG, see later
        end
        e["types"] = nice_types
      }

      # Organisms
      print "Organisms\n"
      exps.each { |e|
        print "."; $stdout.flush
        e["organisms"] = r.get_organisms_for_experiment(e["xschema"])
        e["organisms"].delete_if { |o| o["genus"] == "Unknown" }
      }
      print "\n"

      # Antibodies/reagents?
      # Get data for each experiment
      print "Reagents\n"
      exps.each { |e|
        print "."; $stdout.flush
        data = r.get_data_for_schema(e["xschema"])
        data = data.uniq_by { |d| [ d["heading"], d["name"], d["value"] ] }

        # Pick off the useful data
        # BAM files?
        bam_files = data.find_all { |d| d["type"] =~ /modencode:Sequence_Alignment\/Map \(SAM\)/ }
        if bam_files.size > 0 then
          e["types"] += [ "alignments" ]
        end
        # WIG files?
        wig_files = data.find_all { |d| d["type"] =~ /^modencode:WIG/ }
        if wig_files.size > 0 then
          # Find out what kind of wiggle files after we can look at the protocols
          e["types"] += [ "signal data" ]
        end
        # Specimens:
        e["specimens"] = Array.new
        specimens = data.find_all { |d| d["type"] =~ /MO:((whole_)?organism(_part)?)|(developmental_)?stage|RNA|cell(_line)?|strain_or_line|BioSample/ }
        missing = Array.new
        specimens.each { |d|
          attrs = r.get_attributes_for_datum(d["data_id"], e["xschema"])
          if !( 
            attrs.find { |a| a["heading"] == "official name" }.nil? && 
            attrs.find { |a| a["heading"] == "Cell Type cv" }.nil? &&
            attrs.find { |a| a["heading"] == "developmental stage" }.nil? &&
            attrs.find { |a| a["heading"] == "strain" }.nil? 
            ) then
            d["attributes"] = attrs
            e["specimens"].push d
          elsif attrs.find { |attr| attr["type"] == "modencode:reference" } then
            ref_attr = attrs.find_all { |attr| attr["type"] == "modencode:reference" }
            d["attributes"] = attrs
            e["specimens"].push d
          elsif d["heading"] =~ /Anonymous Datum/ && d["type"] =~ /MO:((whole_)?organism(_part)?)/ then
            d["attributes"] = Array.new
            e["specimens"].push d
          else
            missing.push d
          end
        }
        e["specimens"] = e["specimens"].uniq_by { |d| d["attributes"].nil? ? nil : d["attributes"] }
        if missing.size > 0 then
          if missing.size > 1 then
            e["missing_specimens"] = missing[0...2].map { |d| d["value"] }.join(", ") + ", and #{missing.size - 2} more"
          else
            e["missing_specimens"] = missing[0]["value"]
          end
        end

        # Antibodies
        e["antibodies"] = Array.new
        antibodies = data.find_all { |d| d["type"] =~ /MO:(antibody)/ }
        antibodies.each { |d|
          attrs = r.get_attributes_for_datum(d["data_id"], e["xschema"])
          unless attrs.find { |a| a["heading"] == "official name" }.nil? then
            d["attributes"] = attrs
            e["antibodies"].push d
          end
        }
        e["antibodies"] = e["antibodies"].uniq_by { |d| d["attributes"].nil? ? nil : d["attributes"] }

        # Arrays
        e["arrays"] = Array.new
        arrays = data.find_all { |d| d["type"] =~ /modencode:(ADF)/ }
        arrays.each { |d|
          attrs = r.get_attributes_for_datum(d["data_id"], e["xschema"])
          unless attrs.find { |a| a["heading"] == "official name" }.nil? then
            d["attributes"] = attrs
            e["arrays"].push d
          end
        }
        e["arrays"] = e["arrays"].uniq_by { |d| d["attributes"].nil? ? nil : d["attributes"] }

      }
      print "\n"
      File.open('breakpoint2.dmp', 'w') { |f| Marshal.dump(exps, f) }
    end

    # Experiment overview info (Lab, etc)
    exps.each { |e|
      attrs = r.get_experiment_properties(e["xschema"])
      begin
      e["project"] = attrs.find { |a| a["name"] == "Project" }["value"]
      e["lab"] = attrs.find { |a| a["name"] == "Lab" }["value"]
      rescue
        puts "Can't find project or lab for #{e["xschema"]}"
      end
    }
    File.open('breakpoint3.dmp', 'w') { |f| Marshal.dump(exps, f) }
  end
  # Experiment type
  puts "Protocol types"
  exps.each { |e|
    print "."
    $stdout.flush
    e["protocol_types"] = r.get_protocol_types(e["xschema"])
  }
  File.open('breakpoint4.dmp', 'w') { |f| Marshal.dump(exps, f) }
end

def unescape(str)
  str = CGI.unescapeHTML(str)
  match = str.match(/^"([^"]*)"/)
  match.nil? ? str : match[1]
end

exps.each { |e|
  e["tissue"] = Array.new if e["tissue"].nil?
  e["strain"] = Array.new if e["strain"].nil?
  e["cell_line"] = Array.new if e["cell_line"].nil?
  e["stage"] = Array.new if e["stage"].nil?

  # Pull in any specimens from referenced projects
  referenced_specimens = e["specimens"].find_all { |sp| sp["attributes"].find { |attr| attr["type"] == "modencode:reference" } }
  referenced_specimens.each { |rsp|
    old_experiment_id = rsp["attributes"].find { |attr| attr["type"] == "modencode:reference" }["value"]
    old_experiment = exps.find { |e2| e2["xschema"] =~ /#{old_experiment_id}/ }
    next if (old_experiment_id.nil? || old_experiment_id !~ /^\d+$/)
    old_data = r.get_referenced_data_for_schema(old_experiment["xschema"], rsp["name"], rsp["value"]).uniq_by { |d| [ d["heading"], d["name"], d["value"] ] }
    # Find specimens matching the old data
    old_specimens = old_data.find_all { |d| d["type"] =~ /MO:((whole_)?organism(_part)?)|(developmental_)?stage|RNA|cell(_line)?|strain_or_line|BioSample/ }
    old_specimens.each { |d|
      attrs = r.get_attributes_for_datum(d["data_id"], old_experiment["xschema"])
      if !( 
        attrs.find { |a| a["heading"] == "official name" }.nil? && 
        attrs.find { |a| a["heading"] == "Cell Type cv" }.nil? &&
        attrs.find { |a| a["heading"] == "developmental stage" }.nil? &&
        attrs.find { |a| a["heading"] == "strain" }.nil? 
        ) then
        d["attributes"] = attrs
        e["specimens"].push d
      elsif attrs.find { |attr| attr["type"] == "modencode:reference" } then
        ref_attr = attrs.find_all { |attr| attr["type"] == "modencode:reference" }
        d["attributes"] = attrs
        e["specimens"].push d
      elsif d["heading"] =~ /Anonymous Datum/ && d["type"] =~ /MO:((whole_)?organism(_part)?)/ then
        d["attributes"] = Array.new
        e["specimens"].push d
      end
    }
    e["specimens"] = e["specimens"].uniq_by { |d| d["attributes"].nil? ? nil : d["attributes"] }
    old_data.each { |d|
      old_specimen = old_experiment["specimens"].find { |od| od["data_id"] = d["data_id"] }
      e["specimens"].push(old_specimen) unless old_specimen.nil?
    }
    e["specimens"].uniq!
    # TODO: Referenced protocol types
    old_protocol_types = r.get_protocol_types_for_data_ids(old_data.map { |od| od["data_id"] }.uniq, old_experiment["xschema"])
    e["protocol_types"] += old_protocol_types
    e["specimens"].delete(rsp)
  }
  e["specimens"].each { |sp|
    # Hacky workaround for poorly typed Lai data
    if sp["heading"] =~ /(Parameter|Result) Value/ && sp["type"] =~ /organism_part/ then
      old_type = sp["type"]
      sp["type"] = "MO:cell_line" if sp["value"] =~ /^CellLine/
      sp["type"] = "stage" if sp["value"] =~ /^DevStage/
      sp["attributes"].delete_if { |a| a["heading"] == "official name" } unless sp["type"] == "MO:cell_line"
      puts "  #{e["xschema"]}\tRewrote #{old_type} to #{sp["type"]}" if old_type != sp["type"]
    end
    # Ditto for MacAlpine
    if sp["heading"] =~ /(Parameter|Result) Value|Source Name/ && sp["type"] =~ /BioSample/ then
      # Probably multiple things going on here (Strain, Stage, Cell Line)
      old_type = sp["type"]
      sp["type"] = ""
      sp["type"] += " cell_line" if sp["attributes"].find { |attr| 
        (attr["heading"] =~ /Characteristics?/i && attr["value"] =~ /^CellLine/) ||
          attr["type"] =~ /MO:cell_line/
      }
      sp["type"] += " strain" if sp["attributes"].find { |attr| 
        (attr["heading"] =~ /Characteristics?/i && attr["value"] =~ /Strain/) ||
          attr["type"] =~ /MO:strain_or_line/
      }
      sp["type"] += " stage" if sp["attributes"].find { |attr| 
        (attr["heading"] =~ /Characteristics?/i && attr["value"] =~ /Stage/) ||
          attr["type"] =~ /MO:developmental_stage/
      }
      sp["type"].gsub!(/^\s*|\s*$/, '')
      puts "  #{e["xschema"]}\tRewrote #{old_type} to #{sp["type"]}" if old_type != sp["type"]
    end
    # Other hacks:
    sp["type"] = "MO:cell_line" if sp["type"] == "MO:cell" # Geez, really? (fixes exp #444)
    sp["type"] = "MO:cell_line" if sp["type"] == "obi-biomaterial:cell line culture" # (ditto #296)
    # /end hacky workarounds
    
    tissue = sp["attributes"].find_all { |attr| attr["heading"] == "tissue" }
    strain = sp["attributes"].find_all { |attr| attr["heading"] == "strain" }

    stage  = sp["attributes"].find_all { |attr| attr["heading"] =~ /stage/ }
    e["tissue"] += tissue.map { |t| t["value"] } unless tissue.size == 0
    e["stage"]  += stage.map  { |s| s["value"]  } unless stage.size == 0
    e["strain"] += strain.map { |s| unescape(s["value"]) } unless strain.size == nil
    if sp["attributes"].find { |attr| attr["heading"] =~ /Characteristics?/ && attr["name"] == "stage" } then
      stage_expand = sp["attributes"].find { |attr| 
        (attr["heading"] =~ /Characteristics?/i && attr["value"] =~ /^Stage/) ||
          attr["type"] =~ /MO:developmental_stage/
      }
      if stage_expand then
        stage += sp["attributes"].find_all { |attr| attr["attr_group"] == stage_expand["attr_group"] && attr["heading"] == "official name" }
      end
      e["stage"] += stage
    end
    if sp["attributes"].find { |attr| attr["heading"] =~ /Characteristics?/ && attr["name"] == "strain" } then
      strain_expand = sp["attributes"].find { |attr| 
        (attr["heading"] =~ /Characteristics?/i && attr["value"] =~ /^Strain/) ||
          attr["type"] =~ /MO:strain_or_line/
      }
      if strain_expand then
        strain = sp["attributes"].find_all { |attr| attr["attr_group"] == strain_expand["attr_group"] && attr["heading"] == "official name" }
      end

      strain =  sp["attributes"].find_all { |attr| attr["heading"] == "official name" } if strain.nil?
      e["strain"] += strain.map { |s| unescape(s["value"]) } unless strain.size == 0
    end
    if sp["heading"] =~ /(Parameter|Result) Value/ && sp["type"] =~ /whole_organism/ then
      strain = sp["attributes"].find_all { |attr| attr["heading"] == "official name" }
      e["strain"] += strain.map { |s| unescape(s["value"]) } unless strain.size == 0
    end
    if sp["heading"] =~ /(Parameter|Result) Value/ && sp["type"] =~ /strain_or_line/ then
      if sp["value"] =~ /Strain/ then
        strain = sp["attributes"].find_all { |attr| attr["heading"] == "official name" }
        e["strain"] += strain.map { |s| unescape(s["value"]) } unless strain.size == 0
      end
    end
    if sp["heading"] =~ /(Source|Sample) Name/ && sp["type"] =~ /whole_organism/ then
      strain = sp["attributes"].find_all { |attr| attr["heading"] == "official name" }
      strain = sp["attributes"].find_all { |attr| attr["heading"] == "strain" } if strain.size == 0
      e["strain"] += strain.map { |s| unescape(s["value"]) } unless strain.size == 0
    end
    if sp["heading"] =~ /(Parameter|Result) Value/ && sp["type"] =~ /organism_part/ then
      tissue = sp["attributes"].find_all { |attr| attr["heading"] == "official name" }
      tissue = sp["attributes"].find_all { |attr| attr["heading"] == "tissue" } if tissue.size == 0
      e["tissue"] += tissue.map { |t| unescape(t["value"]) } unless tissue.size == 0
    end
    if sp["heading"] =~ /(Parameter|Result) Value/ && sp["type"] =~ /RNA/ then
      tissue = sp["attributes"].find_all { |attr| attr["heading"] == "Cell Type cv" }
      e["tissue"] += tissue.map { |t| unescape(t["value"]) } unless tissue.size == 0
    end
    if e["tissue"].size == 0 && sp["heading"] =~ /Anonymous Datum/ && sp["type"] =~ /whole_organism/ then
      tissue = [ "whole organism" ]
      e["tissue"] += tissue if e["tissue"].size == 0
    end
    if sp["heading"] =~ /Anonymous Datum/ && sp["type"] =~ /organism_part/ then
      tissue = [ "organism part - FIXME" ]
      e["tissue"] += tissue if e["tissue"].size == 0
    end
    if sp["heading"] =~ /(Parameter|Result) Value/ && sp["type"] =~ /stage/ then
      stage = sp["attributes"].find_all { |attr| attr["heading"] == "developmental stage" }
      stage = sp["attributes"].find_all { |attr| attr["heading"] == "official name" } if stage.size == 0
      e["stage"] += stage.map { |t| unescape(t["value"]) } unless stage.size == 0
    end
    if sp["type"] =~ /cell_line/ then
      # First, try to find a typed attribute:
      cell_line_expand = sp["attributes"].find { |attr| 
        (attr["heading"] =~ /Characteristics?/i && attr["value"] =~ /^CellLine/) ||
          attr["type"] =~ /MO:cell_line/
      }
      if cell_line_expand then
        cell_line = sp["attributes"].find_all { |attr| attr["attr_group"] == cell_line_expand["attr_group"] && attr["heading"] == "official name" }
      end
      cell_line = sp["attributes"].find_all { |attr| attr["heading"] == "official name" } if (cell_line.nil? || cell_line.size == 0)
      e["cell_line"].push cell_line.map { |t| unescape(t["value"]) } unless cell_line.size == 0
    end
    if sp["type"] =~ /cell_line/ && e["strain"].size == 0 then
      # Cell lines don't have to have strains
      e["strain"] += [ "N/A" ]
    end
    e["strain"].uniq!
    e["strain"].delete("N/A") if e["strain"].size > 1

    if tissue.size == 0 && strain.size == 0 && stage.size == 0 then
      puts tissue.size
      puts "What is #{sp.pretty_inspect} for #{e["xschema"]}"
    end
  }
  e["stage"].map { |s| s.sub!(/^.*development(_|\s)*CV:/, '') } unless e["stage"].nil?
  if e["specimens"].find { |sp| sp["type"] =~ /whole_organism/ } && e["tissue"].size == 0 then
    e["tissue"].push "whole organism" 
  end
  #e["tissue"] = [ "whole organism" ] if e["tissue"].size == 0
  e["tissue"].uniq!
  e["stage"].uniq! unless e["stage"].nil?
}

exps.each { |e|
  e["experiment_types"] = Array.new
  protocol_types = e["protocol_types"].map { |row| row["type"] }
  if 
    protocol_types.find { |pt| pt =~ /nucleic_acid_extraction|RNA extraction/ } && 
    protocol_types.find { |pt| pt =~ /sequencing(_protocol)?/ } && 
    protocol_types.find { |pt| pt =~ /chromatin_immunoprecipitation/ }.nil?
    then
    if protocol_types.find { |pt| pt =~ /reverse_transcription/ } then
      e["experiment_types"].push "RTPCR"
    else
      e["experiment_types"].push "RNA-seq"
    end
  end
  if 
    protocol_types.find { |pt| pt =~ /reverse_transcription/ } && 
    protocol_types.find { |pt| pt =~ /PCR(_amplification)?/ }
    then
      if e["protocol_types"].find { |row| row["description"] =~ /RACE/ } then
        e["experiment_types"].push "RACE"
      else
        e["experiment_types"].push "RTPCR"
      end
  end
  if 
    protocol_types.find { |pt| pt =~ /immunoprecipitation/ }
    then
    if protocol_types.find { |pt| pt =~ /hybridization/ } then
      e["experiment_types"].push "ChIP-chip"
    else
      e["experiment_types"].push "ChIP-seq"
    end
  end
  if 
    protocol_types.find { |pt| pt =~ /hybridization/ } &&
    protocol_types.find { |pt| pt =~ /immunoprecipitation/ }.nil?
    then
    e["experiment_types"].push "RNA tiling array"
  end
  if 
    protocol_types.find { |pt| pt =~ /annotation/i }
    then
    e["experiment_types"].push "Computational annotation"
    if e["experiment_types"].size == 1 then
      e["strain"] = [ "N/A" ]
      e["tissue"] = [ "N/A" ]
      e["stage"] = [ "N/A" ]
      e["cell_line"] = [ "N/A" ]
      e["antibody_names"] = [ "N/A" ]
    end
  end
  if 
    e["experiment_types"].size == 0 && 
    protocol_types.find { |pt| pt =~ /grow/ } && 
    protocol_types.find { |pt| pt =~ /grow/ }
  then
    e["types"] = [ "N/A (metadata only)" ]
    e["experiment_types"].push "RNA sample creation"
    e["antibody_names"] = [ "N/A" ]
  end
  e["experiment_types"].uniq!

  # Any wiggle files that we need to figure out the type for?
  if e["types"].include?("signal data") then
    wig_types = Array.new
    if protocol_types.find { |pt| pt =~ /chromatin_immunoprecipitation/ } then
      wig_types.push "chromatin binding site signal data"
    end
    e["types"].delete("signal data") if wig_types.size > 0
    e["types"] += wig_types
  end

  e["types"].delete("binding sites") if e["types"].include?("chromatin binding sites")
  e["types"].delete("binding sites") if e["types"].include?("chromatin binding site signal data")
}
print "\n"


exps.each { |e|
  e["antibody_names"] = Array.new if e["antibody_names"].nil?
  e["antibodies"].each { |a|
    name = nil
#    name = a["attributes"].find { |attr| attr["heading"] == "target id" }
#    name = (name.nil? || name["value"] == "Not Applicable") ? nil : name["value"]
    if name.nil? then
      name = a["attributes"].find { |attr| attr["heading"] == "target name" }
      name = (name.nil? || name["value"] == "Not Applicable") ? nil : name["value"]
    else
      # Got a target ID, strip the CV
      name = name.sub(/(fly|worm)_genes:/, '')
    end
    if name.nil? then
      name = a["attributes"].find { |attr| attr["heading"] == "official name" }
      name = name["value"] unless name.nil?
    end
    target_id = nil
    e["specimens"].each { |sp| 
      target_id = sp["attributes"].find { |attr| attr["heading"] == "target id" }
      if target_id then
        name = target_id["value"]
        break
      end
    }
    e["antibody_names"].push name
  }
}

# Experiment flags from pipeline
dbh = DBI.connect("dbi:Pg:dbname=pipeline_dev;host=heartbroken.lbl.gov", "db_public", "ir84#4nm")
sth = dbh.prepare("SELECT status, deprecated_project_id FROM projects WHERE id = ?")
exps.each { |e|
  pipeline_id = e["xschema"].match(/_(\d+)_/)[1].to_i
  sth.execute(pipeline_id)
  (status, deprecated) = sth.fetch_array
  e["status"] = status
  e["deprecated"] = (deprecated != "" && !deprecated.nil?)
}
sth.finish
dbh.disconnect

puts "#{exps.size} total projects"
exps.delete_if { |e| e["status"] != "released" || e["deprecated"] }
puts "#{exps.size} released projects"

# Skip known good projects
exps.delete_if { |e| e["xschema"].match(/_(\d+)_/)[1].to_i <= 69 }

exps.sort! { |e1, e2| e1["xschema"].match(/_(\d+)_/)[1].to_i <=> e2["xschema"].match(/_(\d+)_/)[1].to_i }

Formatter::format_html(exps, "output.html")
