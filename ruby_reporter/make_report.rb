#!/usr/bin/ruby

require 'rubygems'
require 'cgi'
require 'dbi'
require 'pp'
require '/var/www/pipeline/submit/lib/pg_database_patch'
require 'formatter'
require 'chado_reporter'
require 'geo'

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
        # Get a list of all the experiments (and their properties)
        exps = r.get_basic_experiments

        # Get GEO IDs
        eutil = Eutils.new
        eutil_result = eutil.esearch("modencode_submission_*")
        eutil_result2 = eutil.esummary(nil, eutil_result[0], eutil_result[1])
        got_summaries = REXML::XPath.match(eutil_result2.elements["eSummaryResult"], "DocSum/Item[@Name='summary']")
        puts "Assigning GEO IDs to experiments"
        got_summaries.each { |summary_element|
          this_docsum = summary_element.parent
          gse = "GSE" + this_docsum.elements["./Item[@Name='GSE']"].text
          gsm = REXML::XPath.match(this_docsum.elements["./Item[@Name='Samples']"], "./Item[@Name='Sample']/Item[@Name='Accession']").map { |i| i.text }
          this_exp = exps.find { |e| 
            e["xschema"].match(/modencode_experiment_(\d+)_data/)[1].to_i == summary_element.text.match(/modencode_submission_(\d+)[^\d]/i)[1].to_i
          }
          if this_exp.nil? then
            puts "Couldn't find experiment matching summary #{summary_element.text}"
            next
          end
          this_exp["GSE"] = gse
          this_exp["GSM"] = gsm
        }
        
        # Save the list of experiments so we can run this script again without regenerating it
        File.open('breakpoint1.dmp', 'w') { |f| Marshal.dump(exps, f) }
      end

      # Get all of the feature types for each experiment, and from them
      # generate a list of "nice" type names. For instance, types containing
      # "intron", "exon", "start_codon", "stop_codon" are all categorized as
      # "splice sites"
      exps.each { |e|
        nice_types = r.get_nice_types(e["types"])
        if nice_types.size == 0 then
          # No feature data!?
          puts "No feature data for experiment #{e["xschema"]}"
          # Still might be BAM or WIG, see later
        end
        e["types"] = nice_types
      }

      # Get all of the organisms for this experiment
      print "Organisms\n"
      exps.each { |e|
        print "."; $stdout.flush
        e["organisms"] = r.get_organisms_for_experiment(e["xschema"])
        e["organisms"].delete_if { |o| o["genus"] == "Unknown" }
      }
      print "\n"

      # Get all of the reagents (antibodies, strains, stages, cell lines) for 
      # each experiment
      print "Reagents\n"
      exps.each { |e|
        print "."; $stdout.flush
        data = r.get_data_for_schema(e["xschema"])
        data = data.uniq_by { |d| [ d["heading"], d["name"], d["value"] ] }

        # Are there any BAM files? If so, add "alignments" to the types
        # of data in this experiment
        bam_files = data.find_all { |d| d["type"] =~ /modencode:Sequence_Alignment\/Map \(SAM\)/ }
        if bam_files.size > 0 then
          e["types"] += [ "alignments" ]
        end

        # Are there any WIG files? If so, add "signal data" to the types
        # of data in this experiment
        wig_files = data.find_all { |d| d["type"] =~ /^modencode:WIG/ }
        if wig_files.size > 0 then
          # Find out what kind of wiggle files after we can look at the protocols
          e["types"] += [ "signal data" ]
        end

        # specimens
        # Get any specimens (cell line, strain, stage) attached to this
        # experiment; requires the correct type(s) (see regex below and
        # filters to make sure it matches the expected style for specimen
        # data
        e["specimens"] = r.collect_specimens(data, e["xschema"])

        # antibodies
        # Get any antibodies attached to this experiment; requires the 
        # correct type (MO:antibody) and for it to be from a wiki page 
        # with an "official name" field
        e["antibodies"] = r.collect_antibodies(data, e["xschema"])

        # microarrays
        # Get any microarrays attached to this experiment; requires the
        # correct type (modencode:ADF) and for it to be from a wiki page
        # with an "official name" field
        e["arrays"] = r.collect_microarrays(data, e["xschema"])

      }
      print "\n"

      # Save a breakpoint here so if something after specimen collection crashes
      # we don't have to query them all from the database again.
      File.open('breakpoint2.dmp', 'w') { |f| Marshal.dump(exps, f) }
    end

    # Get the Project and Lab for each experiment
    exps.each { |e|
      attrs = r.get_experiment_properties(e["xschema"])
      begin
        e["project"] = attrs.find { |a| a["name"] == "Project" }["value"]
        e["lab"] = attrs.find { |a| a["name"] == "Lab" }["value"]
      rescue
        puts "Can't find project or lab for #{e["xschema"]}"
      end
    }
    # Save a breakpoint so we don't have to get the experiment and lab again
    File.open('breakpoint3.dmp', 'w') { |f| Marshal.dump(exps, f) }
  end

  # Get all of the protocol types associated with each experiment
  puts "Protocol types"
  exps.each { |e|
    print "."
    $stdout.flush
    e["protocol_types"] = r.get_protocol_types(e["xschema"])
  }
  # Save a breakpoint so we don't have to get the protocol types again
  File.open('breakpoint4.dmp', 'w') { |f| Marshal.dump(exps, f) }
end

# For all of the specimens that refer to a specimen from an old project, pull
# in any other specimens and protocol types from the old project that happen in
# protocols before the creation of this specimen.  In the case of the Celniker
# RNA samples, this means pulling in the protocol types for growth, RNA
# extraction, organism purification, etc., as well as the data attached to
# those protocols.
exps.each { |e|
  referenced_specimens = e["specimens"].find_all { |sp| sp["attributes"].find { |attr| attr["type"] == "modencode:reference" } }
  referenced_specimens.each { |rsp|
    # Get the old experiment ID from the specimen's DBXref
    old_experiment_id = rsp["attributes"].find { |attr| attr["type"] == "modencode:reference" }["value"]
    old_experiment = exps.find { |e2| e2["xschema"] =~ /#{old_experiment_id}/ }
    next if (old_experiment_id.nil? || old_experiment_id !~ /^\d+$/)

    # Get all of the data from the old experiment that was involved in the 
    # creation of this specimen
    old_data = r.get_referenced_data_for_schema(old_experiment["xschema"], rsp["name"], rsp["value"]).uniq_by { |d| [ d["heading"], d["name"], d["value"] ] }

    # Find all of the specimens in the old_data; this is the same as the code
    # that gets the specimens for the current experiment
    old_specimens = r.collect_specimens(old_data, old_experiment["xschema"])
    e["specimens"] += old_specimens

    e["specimens"] = e["specimens"].uniq_by { |d| d["attributes"].nil? ? nil : d["attributes"] }

    # Get all of the protocol types attached to the data from the old experiment
    old_protocol_types = r.get_protocol_types_for_data_ids(old_data.map { |od| od["data_id"] }.uniq, old_experiment["xschema"])
    e["protocol_types"] += old_protocol_types

    # Delete the current specimen, since we've replaced it with the old one
    e["specimens"].delete(rsp)
  }
}

############################################################################
# Okay, we've fetched (almost) all of the data we want about these experiments, 
# so now we try to translate it into something useful.

# Search through all of the "specimen" data to see if we can discover the 
# tissue, strain, cell line, and/or stage of the organism(s) involved.
exps.each { |e|
  e["tissue"] = Array.new if e["tissue"].nil?
  e["strain"] = Array.new if e["strain"].nil?
  e["cell_line"] = Array.new if e["cell_line"].nil?
  e["stage"] = Array.new if e["stage"].nil?

  e["specimens"].each { |sp|
    ####
    # Hacky workarounds for poorly typed data
    ###

    # Some of the older Lai data has both cell lines and stages typed as "organism_part",
    # so we see if it's referring to a wiki page (.*CellLine.* or .*DevStage.*) to determine
    # the type.
    if sp["heading"] =~ /(Parameter|Result) Value/ && sp["type"] =~ /organism_part/ then
      old_type = sp["type"]
      sp["type"] = "MO:cell_line" if sp["value"] =~ /^CellLine/
      sp["type"] = "stage" if sp["value"] =~ /^DevStage/
      sp["attributes"].delete_if { |a| a["heading"] == "official name" } unless sp["type"] == "MO:cell_line"
      # Print to console to let us know we've made up a type here
      puts "  #{e["xschema"]}\tRewrote #{old_type} to #{sp["type"]}" if old_type != sp["type"]
    end

    # MacAlpine data often has data typed as BioSample, which then have multiple "Characteristics"
    # columns; one for stage, one for cell line, etc. This checks to see if those Characteristics
    # are explicitly typed (e.g. "Characteristic [line] (MO:cell_line)" in the SDRF), and if so,
    # assigns those types to the parent datum.
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
      # Print to console to let us know we're inherting a type here
      puts "  #{e["xschema"]}\tRewrote #{old_type} to #{sp["type"]}; inherited from attributes" if old_type != sp["type"]
    end
    # Other hacks for strange ontology terms:
    sp["type"] = "MO:cell_line" if sp["type"] == "MO:cell" # Geez, really? (fixes exp #444)
    sp["type"] = "MO:cell_line" if sp["type"] == "obi-biomaterial:cell line culture" # (ditto #296)
    ####
    # /end hacky workarounds
    ###
    
    # By default, just look for attributes titled "tissue", "strain", or "stage" to get the tissue,
    # strain, and stage. (E.g. "SomeAttribute [tissue]".)
    if sp["attributes"].nil? then
      puts sp.pretty_inspect
    end
    stage  = sp["attributes"].find_all { |attr| attr["heading"] =~ /stage/ }
    tissue = sp["attributes"].find_all { |attr| attr["heading"] == "tissue" }
    strain = sp["attributes"].find_all { |attr| attr["heading"] == "strain" }

    # Get the values of tissue, strain, and stage, rather than the whole datum
    e["stage"]  += stage.map  { |s| s["value"]  } unless stage.size == 0
    e["tissue"] += tissue.map { |t| t["value"] } unless tissue.size == 0
    e["strain"] += strain.map { |s| r.unescape(s["value"]) } unless strain.size == nil

    # Okay, now we get into the complex heuristics where we try to sort out the reagent
    # information based on various types and headings

    #############
    #   STAGE   #
    #############
    # Are there any "Characteristics [stage]" attributes attached to this specimen? If so, 
    # do they contain "Stage", implying a stage from a wiki page, or are they explicitly 
    # typed as MO:developmental stage? If yes, then get the "official name" from the wiki
    # page and store it as a stage.
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
    # How about any "Parameter/Result Value" columns with a type containing "stage" and 
    # an attribute with a heading of "developmental stage" or "official name"? If yes, 
    # get that attribute's value and save it as a stage.
    if sp["heading"] =~ /(Parameter|Result) Value/ && sp["type"] =~ /stage/ then
      stage = sp["attributes"].find_all { |attr| attr["heading"] == "developmental stage" }
      stage = sp["attributes"].find_all { |attr| attr["heading"] == "official name" } if stage.size == 0
      e["stage"] += stage.map { |t| r.unescape(t["value"]) } unless stage.size == 0
    end
    # What about just a simple data column typed as developmental_stage with a DBXref
    # into the (worm|fly)_development CV?
    if sp["type"] =~ /developmental_stage/ && !sp["dbxref"].nil? then
      if stage = sp["dbxref"].match(/development:(.+$)/) then
        stage = sp["dbxref"].match(/development:(.+)$/)[1]
        e["stage"].push stage
      end
    end


    #############
    #  TISSUE   #
    #############
    # Are there any "Parameter/Result Value" columns with a type containing "organism_part"
    # and an attribute with a heading of "tissue" or "official name"? If yes, get that
    # attribute's value and save it as a tissue.
    if sp["heading"] =~ /(Parameter|Result) Value/ && sp["type"] =~ /organism_part/ then
      tissue = sp["attributes"].find_all { |attr| attr["heading"] == "official name" }
      tissue = sp["attributes"].find_all { |attr| attr["heading"] == "tissue" } if tissue.size == 0
      e["tissue"] += tissue.map { |t| r.unescape(t["value"]) } unless tissue.size == 0
    end
    # How about "Parameter/Result Value" columns with a type containing "RNA" and an
    # attribute with a heading of "Cell Type cv"? There are some wiki pages like this, 
    # particularly from Lai data. If we find one, get the attributes value, and save it
    # as an additional tissue.
    if sp["heading"] =~ /(Parameter|Result) Value/ && sp["type"] =~ /RNA/ then
      tissue = sp["attributes"].find_all { |attr| attr["heading"] == "Cell Type cv" }
      e["tissue"] += tissue.map { |t| r.unescape(t["value"]) } unless tissue.size == 0
    end
    # If we haven't yet found a tissue, is there an Anonymous Datum (a datum between
    # two protocols not explicitly shown in the SDRF) of type "whole_organism"? If so, 
    # then lets assume the tissue in this case is the whole organism.
    if e["tissue"].size == 0 && sp["heading"] =~ /Anonymous Datum/ && sp["type"] =~ /whole_organism/ then
      tissue = [ "whole organism" ]
      e["tissue"] += tissue
    end
    # If we haven't yet found a tissue, is there an Anonymous Datum (a datum between
    # two protocols not explicitly shown in the SDRF) of type "whole_organism"? If so, 
    # then lets assume the tissue in this case is an organism_part. Since this is 
    # super-vague, let's actually label it "organism part - FIXME" so that we make
    # sure to fix the original submission
    if sp["heading"] =~ /Anonymous Datum/ && sp["type"] =~ /organism_part/ then
      tissue = [ "organism part - FIXME" ]
      e["tissue"] += tissue if e["tissue"].size == 0
    end

    #############
    #  STRAIN   #
    #############
    # Are there any "Characteristics [strain]" attributes attached to this specimen? If so, 
    # do they contain "Strain", implying a stage from a wiki page, or are they explicitly 
    # typed as MO:strain_or_line? If yes, then look for an attribute from the same wiki
    # page (attr_group) with a heading of "official name" and store its value as a stage.
    if sp["attributes"].find { |attr| attr["heading"] =~ /Characteristics?/ && attr["name"] == "strain" } then
      strain_expand = sp["attributes"].find { |attr| 
        (attr["heading"] =~ /Characteristics?/i && attr["value"] =~ /^Strain/) ||
          attr["type"] =~ /MO:strain_or_line/
      }
      if strain_expand then
        strain = sp["attributes"].find_all { |attr| attr["attr_group"] == strain_expand["attr_group"] && attr["heading"] == "official name" }
      end
      e["strain"] += strain.map { |s| r.unescape(s["value"]) } unless strain.size == 0
    end
    # Are there any "Parameter/Result Value" or "Source/Sample Name" columns with a type 
    # containing "strain_or_line", a value containing "Strain", and an attribute with a 
    # heading of "strain" or "official name"? If yes, get that attribute's value and 
    # save it as a strain.
    if sp["heading"] =~ /((Parameter|Result) Value)|((Source|Sample) Name)/ && sp["type"] =~ /strain_or_line/ then
      if sp["value"] =~ /Strain/ then
        strain = sp["attributes"].find_all { |attr| attr["heading"] == "strain" } # Engineered strain
        strain = sp["attributes"].find_all { |attr| attr["heading"] == "official name" } if strain.size == 0  # Regular strain pages
        e["strain"] += strain.map { |s| r.unescape(s["value"]) } unless strain.size == 0
      end
    end
    # Are there any "Parameter/Result Value" or "Source/Sample Name" columns with a type 
    # containing "whole_organism" and an attribute with a heading of "strain" or 
    # "official name"? If yes, get that attribute's value and save it as a strain.
    if sp["heading"] =~ /((Parameter|Result) Value)|((Source|Sample) Name)/ && sp["type"] =~ /whole_organism/ then
      strain = sp["attributes"].find_all { |attr| attr["heading"] == "strain" } # Engineered strain
      strain = sp["attributes"].find_all { |attr| attr["heading"] == "official name" } if strain.size == 0  # Regular strain pages
      e["strain"] += strain.map { |s| r.unescape(s["value"]) } unless strain.size == 0
    end
    # It's not N/A if anything was found, duh.
    e["strain"].delete("N/A") if e["strain"].uniq.size > 1

    #############
    # CELL LINE #
    #############
    # Are there any data (from any column) with a type containing "cell_line", and an
    # attribute with a heading of "Characteristics" and a value containing CellLine, OR
    # an attribute explicitly typed as MO:cell_line? If so, look for an attribute
    # from the same wiki page (attr_group) with a heading of "official name" and store
    # its value as a cell_line. If no "official name" is found in the same group, look
    # for any "official name" attribute of this specimen (since it's already typed as
    # cell_line) and use that instead.
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
      e["cell_line"].push cell_line.map { |t| r.unescape(t["value"]) } unless cell_line.size == 0
    end

    #############
    #  CLEANUP  #
    #############
    # If this is a cell_line specimen, then we may not need a strain, so add
    # "N/A" to the list of strains if we haven't otherwise found one yet. We
    # can clean this up later (see "It's not N/A if anything was found",
    # above).
    if sp["type"] =~ /cell_line/ && e["strain"].size == 0 then
      # Cell lines don't have to have strains
      e["strain"] += [ "N/A" ]
    end

    # If we didn't find a tissue, strain, stage, or cell_line from this specimen,
    # then it's not much of a specimen, is it? Whine about it so we can either add
    # a new case for it or fix the submission.
    if e["tissue"].size == 0 && e["strain"].size == 0 && e["stage"].size == 0 && e["cell_line"].size == 0 then
      puts tissue.size
      puts "What is #{sp.pretty_inspect} for #{e["xschema"]}"
    end
  }

  # Strip any leading CV name from stages, e.g. "FlyBase development CV:"
  e["stage"].map { |s| s.sub!(/^.*development(_|\s)*CV:/, '') } unless e["stage"].nil?

  # If we _still_ haven't found out what tissue was used, and _any_ specimen has
  # a type of "whole_organism", we'll go with that
  if e["specimens"].find { |sp| sp["type"] =~ /whole_organism/ } && e["tissue"].size == 0 then
    e["tissue"].push "whole organism" 
  end

  e["strain"].uniq!
  e["tissue"].uniq!
  e["cell_line"].uniq!
  e["stage"].uniq! unless e["stage"].nil?
}

# Search through all of the protocol types to figure out the type of the 
# experiment
exps.each { |e|
  e["experiment_types"] = Array.new
  protocol_types = e["protocol_types"].map { |row| row["type"] }
  # extraction + sequencing + reverse transcription - ChIP = RTPCR
  # extraction + sequencing - reverse transcription - ChIP = RNA-seq
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

  # reverse transcription + PCR + RACE = RACE
  # reverse transcription + PCR - RACE = RTPCR
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

  # ChIP + hybridization = ChIP-chip
  # ChIP - hybridization = ChIP-seq
  if 
    protocol_types.find { |pt| pt =~ /immunoprecipitation/ }
    then
    if protocol_types.find { |pt| pt =~ /hybridization/ } then
      e["experiment_types"].push "ChIP-chip"
    else
      e["experiment_types"].push "ChIP-seq"
    end
  end

  # hybridization - ChIP = RNA tiling array
  if 
    protocol_types.find { |pt| pt =~ /hybridization/ } &&
    protocol_types.find { |pt| pt =~ /immunoprecipitation/ }.nil?
    then
    e["experiment_types"].push "RNA tiling array"
  end

  # annotation = Computational annotation
  if 
    protocol_types.find { |pt| pt =~ /annotation/i }
    then
    e["experiment_types"].push "Computational annotation"
    # Also get rid of any reagents, since this really just analyzing old data
    if e["experiment_types"].size == 1 then
      e["strain"] = [ "N/A" ]
      e["tissue"] = [ "N/A" ]
      e["stage"] = [ "N/A" ]
      e["cell_line"] = [ "N/A" ]
      e["antibody_names"] = [ "N/A" ]
    end
  end

  # If we haven't found a type yet, and there is a growth protocol, then
  # this is probably an RNA sample creation experiment from Celniker
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

  # If this experiment had signal data and used ChIP, then it made
  # "chromatin binding site signal data", not just generic signal data,
  # so replace the generic type with the specific one.
  if e["types"].include?("signal data") then
    wig_types = Array.new
    if protocol_types.find { |pt| pt =~ /chromatin_immunoprecipitation/ } then
      wig_types.push "chromatin binding site signal data"
    end
    e["types"].delete("signal data") if wig_types.size > 0
    e["types"] += wig_types
  end

  # If we have specific types of binding sites, then get rid of the generic
  # "binding sites"
  e["types"].delete("binding sites") if e["types"].include?("chromatin binding sites")
  e["types"].delete("binding sites") if e["types"].include?("chromatin binding site signal data")
}
print "\n"

# Search through all of the antibody data to try to find antibody names
exps.each { |e|
  e["antibody_names"] = Array.new if e["antibody_names"].nil?
  e["antibodies"].each { |a|
    # Any attributes of this datum with a heading of "target name"? If so, we'll
    # use that rather than the antibody name, since the target is really the 
    # information of interest
    name = a["attributes"].find { |attr| attr["heading"] == "target name" }
    # If there's an empty target or it contains "Not Applicable", look elsewhere.
    # Otherwise, get the value of the attribute.
    name = (name.nil? || name["value"] == "Not Applicable") ? nil : name["value"]
    # If not a target name on an antibody, what about a target ID attached to a
    # specimen in this project?
    e["specimens"].each { |sp| 
      target_id = sp["attributes"].find { |attr| attr["heading"] == "target id" }
      if target_id then
        name = target_id["value"]
        break
      end
    }
    # If we didn't find a target name, look for an attribute (from the wiki
    # page) with a heading of "official name"; this is just the name of
    # the antibody
    if name.nil? then
      name = a["attributes"].find { |attr| attr["heading"] == "official name" }
      name = name["value"] unless name.nil?
    end

    e["antibody_names"].push name
  }
}

# Throw out any deprecated or unreleased projects; look up the status in the pipeline
# database, which is separate from Chado
# Also, grab creation and release dates
dbh = DBI.connect("dbi:Pg:dbname=pipeline_dev;host=heartbroken.lbl.gov", "db_public", "ir84#4nm")
sth = dbh.prepare("SELECT status, deprecated_project_id, created_at FROM projects WHERE id = ?")
sth_release_date = dbh.prepare("SELECT MAX(c.end_time) AS release_date FROM commands c 
                               INNER JOIN projects p ON p.id = c.project_id 
                               WHERE c.type = 'Release' AND c.status = 'released' GROUP BY p.id HAVING p.id = ?")
exps.each { |e|
  pipeline_id = e["xschema"].match(/_(\d+)_/)[1].to_i
  sth.execute(pipeline_id)
  (status, deprecated, created_at) = sth.fetch_array
  e["status"] = status
  e["deprecated"] = (deprecated != "" && !deprecated.nil?)
  e["created_at"] = created_at
  sth_release_date.execute(pipeline_id)
  e["released_at"] = sth_release_date.fetch_array
}
sth.finish
sth_release_date.finish
dbh.disconnect

puts "#{exps.size} total projects"
exps.delete_if { |e| e["status"] != "released" || e["deprecated"] }
puts "#{exps.size} released projects"

# Sort the projects by ID
exps.sort! { |e1, e2| e1["xschema"].match(/_(\d+)_/)[1].to_i <=> e2["xschema"].match(/_(\d+)_/)[1].to_i }

# Output to HTML
if ARGV[0] && ARGV[0].length > 0 && Formatter.respond_to?("format_#{ARGV[0]}") then
  Formatter::send("format_#{ARGV[0]}", exps, ARGV[1])
elsif ARGV[0] && ARGV[0].length > 0 then
  $stderr.puts "Unknown option: #{ARGV[0]}"
  $stderr.puts "  Usage:"
  $stderr.puts "    ./make_report.rb [" + Formatter.methods.find_all { |m| m =~ /^format_/ }.map { |m| m.match(/^format_(.*)/)[1] }.join(", ") + "] [outputfile]"
else
  Formatter::format_html(exps, ARGV[1])
end

