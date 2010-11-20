#!/usr/bin/ruby

require 'rubygems'
require 'cgi'
if File.exists?('dbi_patch.rb') then
  require 'dbi_patch.rb'
else
  require 'dbi'
  require 'dbd/Pg'
end
require 'pp'
#require '/var/www/submit/lib/pg_database_patch'
require 'formatter'
require 'chado_reporter'
require 'geo'
require 'escape'

module Enumerable
  def uniq_by
    h = {}; inject([]) { |a,x| h[yield(x)] ||= a << x }
  end
end

def is_histone_antibody(antibody)
  if antibody =~ /(?:^|[Hh]istone )H\d+(([A-Z]\d.*|[Tt]etra)([Mm][Ee]|[Aa][Cc]|[Bb]ubi))?/
    puts "Modification site change because antibody is #{antibody}"
    if antibody =~ /[tT]rimethylated Lys-(\d+) o[fn] histone (H\d+)/ then
      m = antibody.match(/[tT]rimethylated Lys-(\d+) o[fn] histone (H\d+)/)
      antibody = "#{m[2]}K#{m[1]}Me3"
    else
      antibody = "" + antibody # Clone
    end
    matches = antibody.match(/(?:^|[Hh]istone )(H\d+(([A-Z]\d+|[Tt]etra|[Bb])?(-)?([Mm][Ee]|[Aa][Cc]|[Uu]bi(q)?)(\d*))?([sS]\d+[pP])?([Tt]etra)?\d*)(.*\((.+)\))?/)
    antibody = matches[1]
    antibody_name = matches[11]
    antibody_name = "" if (antibody_name.nil? || antibody_name =~ /lot/)
    antibody.sub!(/-/, '')
    antibody.sub!(/[Aa][Cc](\d)?/, 'Ac\1')
    antibody.sub!(/[Mm][Ee](\d)?/, 'Me\1')
    antibody.sub!(/[Bb]ubi/, 'BUbi')
    antibody.sub!(/[sS](\d+)[pP]/, 'S\1P')
    antibody.sub!(/tetra/, 'Tetra')
    puts "  Cleaned antibody to #{antibody}"

    antibody_name = "#{antibody} #{antibody_name}" unless antibody_name.empty?
    return [ antibody, antibody_name ]
  end
  return false
end


r = ChadoReporter.new
r.set_schema("reporting")

dbh = DBI.connect("dbi:Pg:dbname=pipeline_dev;host=modencode-db1;port=5432", "db_public", "ir84#4nm")
if (File.exists?('breakpoint6.dmp')) then
  exps = Marshal.load(File.read('breakpoint6.dmp'))
else
  if (File.exists?('breakpoint5.dmp')) then
    exps = Marshal.load(File.read('breakpoint5.dmp'))
  else
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

            # Get GEO IDs from NCBI
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
            e["all_data"] = data

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

            e["compound"] = r.collect_compounds(data, e["xschema"])

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

    puts "Checking for referenced submissions."
    exps.each { |e|
      # I have an SRA ID and I need to find it in an old experiment
      # Then I need to folow the graph in the old experiment to collect speciments
      # Including watching out for any further references to even older experiments
      specimens_by_schema = r.recursively_find_referenced_specimens(e["xschema"], e["specimens"])

      all_specimens = specimens_by_schema.values.flatten(1)
      e["all_specimens"] = e["specimens"] = all_specimens

    }
    puts "Done."

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
      e["compound"] = Array.new if e["compound"].nil?
      e["array_platform"] = Array.new if e["array_platform"].nil?
      e["growth_condition"] = Array.new if e["growth_condition"].nil?
      e["rnai_targets"] = Array.new if e["rnai_targets"].nil?
      e["sra_ids"] = Array.new if e["sra_ids"].nil?


      filtered_compounds = Array.new
      e["compound"].each { |compound|
        if compound.is_a?(Hash) then
          compound["name"].sub!(/ concentration$/, '')
          cmp = "#{compound["value"]}"
          concentration_unit = compound["attributes"].find { |attr| attr["name"] == "ConcentrationUnit" }
          cmp += concentration_unit["value"] unless concentration_unit.nil?
          cmp += " #{compound["name"]}"
          filtered_compounds.push cmp
        else
          filtered_compounds.push e["compound"]
        end
      }
      e["compound"] = filtered_compounds

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
              attr["type"] =~ /MO:cell_line|MO:CellLine/
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
  #      if sp["attributes"].nil? then
  #        puts sp.pretty_inspect
  #      end
        sp["attributes"] = [] if sp["attributes"].nil?
        stage  = sp["attributes"].find_all { |attr| attr["heading"] =~ /stage/ }
        tissue = sp["attributes"].find_all { |attr| attr["heading"] == "tissue" }
        strain = sp["attributes"].find_all { |attr| attr["heading"] == "strain" }

        # Get the values of tissue, strain, and stage, rather than the whole datum
        e["stage"]  += stage.map  { |s| s["value"]  } unless stage.size == 0
        e["tissue"] += tissue.map { |t| t["value"] } unless tissue.size == 0
        strain.each { |attr| attr["type"] = "MO:strain_or_line" }
        e["strain"] += strain unless strain.size == 0

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
          e["stage"] += stage.map { |s| s["value"] }
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
            #stage = sp["dbxref"].match(/development:(.+)$/)[1]
            stage = sp["value"]
            e["stage"].push stage
          end
        end
        # What about a Characteristic that's actually been typed as MO:developmental_stage?
        stage_attr = sp["attributes"].find { |attr| attr["heading"] =~ /Characteristics?/ && attr["type"] =~ /MO:developmental_stage/ }
        if stage_attr && stage.size == 0 then
          stage = stage_attr["value"]
          e["stage"].push stage unless (stage.nil? || stage.length == 0)
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
        # then lets assume the tissue in this case is an organism_part. Since this is 
        # super-vague, let's actually label it "organism part - FIXME" so that we make
        # sure to fix the original submission
        if sp["heading"] =~ /Anonymous Datum/ && sp["type"] =~ /organism_part/ then
          tissue = [ "organism part - FIXME" ]
          e["tissue"] += tissue if e["tissue"].size == 0
        end

        if e["tissue"].size == 0 && e["specimens"].find { |sp2| sp2["type"] =~ /MO:(whole_)?organism/ } then
          e["tissue"] += [ "whole organism" ]
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
          strain.each { |attr| attr["type"] = "MO:strain_or_line" }
          strain.each { |attr| attr["title"] = sp["name"] }
          e["strain"] += strain unless strain.size == 0
        end
        # Are there any "Parameter/Result Value" or "Source/Sample Name" columns with a type 
        # containing "strain_or_line", a value containing "Strain", and an attribute with a 
        # heading of "strain" or "official name"? If yes, get that attribute's value and 
        # save it as a strain.
        if sp["heading"] =~ /((Parameter|Result) Value)|((Source|Sample) Name)/ && sp["type"] =~ /strain_or_line/ then
          if sp["value"] =~ /Strain/ then
            strain = sp["attributes"].find_all { |attr| attr["heading"] == "strain" } # Engineered strain
            strain = sp["attributes"].find_all { |attr| attr["heading"] == "official name" } if strain.size == 0  # Regular strain pages
            strain.each { |attr| attr["type"] = sp["type"] }
            strain.each { |attr| attr["title"] = sp["name"] }
            e["strain"] += strain unless strain.size == 0
          end
        end
        # Are there any "Parameter/Result Value" or "Source/Sample Name" columns with a type 
        # containing "whole_organism" and an attribute with a heading of "strain" or 
        # "official name"? If yes, get that attribute's value and save it as a strain.
        if sp["heading"] =~ /((Parameter|Result) Value)|((Source|Sample) Name)/ && sp["type"] =~ /MO:(whole_)?organism/ then
          strain = sp["attributes"].find_all { |attr| attr["heading"] == "strain" } # Engineered strain
          strain = sp["attributes"].find_all { |attr| attr["heading"] == "official name" } if strain.size == 0  # Regular strain pages
          strain.each { |attr| attr["type"] = sp["type"] }
          strain.each { |attr| attr["title"] = sp["name"] }
          e["strain"] += strain unless strain.size == 0
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
        if sp["type"] =~ /cell_line|CellLine/ then
          # First, try to find a typed attribute:
          cell_line_expand = sp["attributes"].find { |attr| 
            (attr["heading"] =~ /Characteristics?/i && attr["value"] =~ /^CellLine/) ||
              attr["type"] =~ /MO:cell_line|MO:CellLine/
          }
          if cell_line_expand then
            cell_line = sp["attributes"].find_all { |attr| attr["attr_group"] == cell_line_expand["attr_group"] && attr["heading"] == "official name" }
          end
          blank_cell_line = sp["attributes"].find { |attr| attr["type"] =~ /MO:cell_line|MO:CellLine/ }
          cell_line = sp["attributes"].find_all { |attr| attr["heading"] == "official name" } if (blank_cell_line.nil? && (cell_line.nil? || cell_line.size == 0))
          e["cell_line"].push cell_line.map { |t| r.unescape(t["value"]) } unless cell_line.size == 0
        end

        #############
        # PLATFORM  #
        #############
        if sp["type"] =~ /modencode:ADF/ then
          array_platform = sp["attributes"].find_all { |attr| attr["heading"] == "platform" }
          e["array_platform"].push array_platform.map { |t| r.unescape(t["value"]) } unless array_platform.size == 0
        end

        #############
        # COMPOUND  #
        #############
        if sp["type"] =~ /MO:genomic_DNA/ then
          compound = sp["attributes"].find_all { |attr| attr["type"] =~ /MO:Compound/i }
          if (compound.size > 0) then
            unit = sp["attributes"].find_all { |attr| attr["heading"] =~ /Unit/i }
            dose = sp["attributes"].find_all { |attr| attr["name"] =~ /Dose/i }
            if (unit.size > 0 && dose.size > 0) then
              e["compound"].push "#{dose[0]["value"]}#{unit[0]["value"]} #{compound[0]["value"]}"
            else
            end
          end
        end


        #############
        #  SRA IDs  #
        #############
        if sp["type"] =~ /modencode:ShortReadArchive_project_ID \(SRA\)/ then
          e["sra_ids"].push sp["value"]
        elsif sp["type"] =~ /modencode:ShortReadArchive_project_ID_list \(SRA\)/ then
          sra_ids = sp["value"].split(/;/).map { |id| id.match(/^(SRA[^\.])*\./)[1] }
          sra_ids.uniq!
          puts "Got: #{sra_ids.join(";")}"
          e["sra_ids"].push sra_ids
        end


        ###############
        # RNAi TARGET #
        ###############
        if sp["type"] =~ /SO:RNAi_reagent/ then
          target = sp["attributes"].find_all { |attr| attr["heading"] =~ /target id/ }
          unless target.size == 0
            e["rnai_targets"].push target.map { |t| r.unescape(t["value"]) }
          end
        end

        ####################
        # GROWTH CONDITION #
        ####################
        if sp["type"] =~ /MO:GrowthCondition/ then
          e["growth_condition"].push r.unescape("#{sp["name"]}:#{sp["value"]}") if sp["value"].length > 0
        end

        #############
        #  CLEANUP  #
        #############
        # If this is a cell_line specimen, then we may not need a strain, so add
        # "N/A" to the list of strains if we haven't otherwise found one yet. We
        # can clean this up later (see "It's not N/A if anything was found",
        # above).
        if sp["type"] =~ /CellLine|cell_line/ && e["strain"].size == 0 then
          # Cell lines don't have to have strains
          e["strain"] += [ "N/A" ]
        end

        # If we didn't find a tissue, strain, stage, or cell_line from this specimen,
        # then it's not much of a specimen, is it? Whine about it so we can either add
        # a new case for it or fix the submission.
        if e["tissue"].size == 0 && e["strain"].size == 0 && e["stage"].size == 0 && e["cell_line"].size == 0 && e["array_platform"].size == 0 && e["compound"].size == 0 && e["growth_condition"].size == 0 && e["sra_ids"].size == 0 then
          puts "What is #{sp.pretty_inspect} for #{e["xschema"]}"
        end
      }

      # If we haven't yet found a tissue, is there any datum of type "whole_organism"?
      # If so, then lets assume the tissue in this case is the whole organism.
      if e["tissue"].size == 0 && e["specimens"].find { |sp2| sp2["type"] =~ /MO:(whole_)?organism/ } then
        e["tissue"] += [ "whole organism" ]
      end

      # Strip any leading CV name from stages, e.g. "FlyBase development CV:"
      e["stage"].map { |s| 
        s.sub!(/^.*development(_|\s)*CV:/, '')
      } unless e["stage"].nil?

      # If we _still_ haven't found out what tissue was used, and _any_ specimen has
      # a type of "whole_organism", we'll go with that
      if e["specimens"].find { |sp2| sp2["type"] =~ /MO:(whole_)?organism/ } && e["tissue"].size == 0 && e["sra_ids"].size == 0 then
        e["tissue"].push "whole organism" 
      end
      #
      # If we found multiple strains, and some are named strain and some are named 
      # something else (like tissue), then keep only the strain-named ones
      strain_titled_strains = e["strain"].find_all { |s| s["title"] =~ /strain/ }
      if strain_titled_strains.size > 0 && e["strain"].size > strain_titled_strains.size then
        e["strain"] = strain_titled_strains
      end
      e["strain"] = e["strain"].map { |strain| strain.is_a?(Hash) ? strain["value"] : strain }

      e["array_platform"].push("N/A") if e["array_platform"].size == 0
      e["strain"].uniq!
      e["tissue"].uniq!
      e["cell_line"].uniq!
      e["array_platform"].uniq!
      e["compound"].uniq!
      e["growth_condition"].uniq!
      e["stage"].uniq! unless e["stage"].nil?

      e["tissue"] = [ "whole organism" ] if e["tissue"].size == 0 && e["strain"].size > 0

      if e["tissue"].size > 1 && e["tissue"].include?("whole organism") then
        e["tissue"] -= ["whole organism"]
      end

    }


    # Figure out DNAse treatment based on protocol names
    exps.each { |e|
      if e["protocol_types"].find { |row| row["name"] =~ /no dnase/i } then
        e["dnase_treatment"] = "no"
      else
        e["dnase_treatment"] = ""
      end
    }


    # Get any GEO IDs from Chado
    puts "  Getting GEO IDs for submissions"
    exps.each { |e|
      print "."; $stdout.flush
      geo_ids = r.get_geo_ids_for_schema(e["xschema"])
      e["GSM"] = Array.new if e["GSM"].nil?
      e["GSM"] += geo_ids unless geo_ids.nil?
    }
    puts "\n"

    # Search through all of the protocol types to figure out the type of the 
    # experiment
    exps.each { |e|
      protocol_types = e["protocol_types"].map { |row| row["type"] }

      e["experiment_types"] = r.get_assay_type(e["xschema"]).map { |type| type == "" ? nil : type }.compact # Is it in the DB?
      if e["experiment_types"].size > 0 && !e["experiment_types"][0].empty? then
        # Use existing assay type
        type = e["experiment_types"][0]
        type.sub!(/Computational Annotation/i, "Computational annotation")
        type.sub!(/Sample Creation/i, "Sample creation")
        type.sub!(/tiling array:\s*RNA/i, "tiling array: RNA")
        e["experiment_types"][0] = type

        if type =~ /Gene Structure/ then
          e["experiment_types"] = [ "gene model" ]
        end
        if type =~ /Sample creation/i then
          e["types"] = [ "N/A (metadata only)" ]
        elsif (type =~ /ChIP/ || type =~ /tiling array: DNA/) && e["types"].include?("signal data") then
          e["types"].delete("signal data")
          e["types"].push("chromatin binding site signal data")
          if e["uniquename"] =~ /replication timing/i then
            e["types"] = [ "replication timing" ]
          elsif e["uniquename"] =~ /origin/i then
            e["types"] = [ "origins of replication" ]
          elsif e["uniquename"] =~ /(orc|mcm)[^a-z]/i then
            e["types"] = [ "replication factors" ]
          end
        elsif type =~ /CAGE/ then
          e["types"] = [ "RNA profiling" ]
        else
          e["types"].delete("binding sites") if e["types"].include?("chromatin binding sites")
          e["types"].delete("binding sites") if e["types"].include?("chromatin binding site signal data")
          if e["types"].size == 0 && (
            (!e["GSE"].nil? && e["GSE"].length > 0) ||
            e["GSM"].size > 0 ||
            e["sra_ids"].size > 0
          ) then
          e["types"].push "raw sequences"
          end
        end
        print "."
        next
      end

      # hybridization - ChIP = RNA tiling array
      # extraction + sequencing + reverse transcription - ChIP = RTPCR
      # extraction + sequencing - reverse transcription - ChIP = RNA-seq
      if 
        protocol_types.find { |pt| pt =~ /nucleic acid extraction|nucleic_acid_extraction|RNA extraction/ } && 
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
        protocol_types.find { |pt| pt =~ /^extraction$/ } &&  # DNA-seq, probably
        protocol_types.find { |pt| pt =~ /sequencing(_protocol)?/ } && 
        protocol_types.find { |pt| pt =~ /chromatin_immunoprecipitation/ }.nil?
        then
        if protocol_types.find { |pt| pt =~ /reverse_transcription/ } then
          e["experiment_types"].push "RTPCR"
        else
          e["experiment_types"].push "DNA-seq"
        end
      end

      if e["rnai_targets"].size > 0 then
        e["experiment_types"].push "RNAi"
      end

      # reverse transcription + PCR + RACE = RACE
      # reverse transcription + PCR - RACE = RTPCR
      if 
        protocol_types.find { |pt| pt =~ /reverse_transcription/ } && 
        protocol_types.find { |pt| pt =~ /PCR(_amplification)?/ }
        then
          if e["types"].size > 0 then
            if e["protocol_types"].find { |row| row["description"] =~ /RACE/ } then
              e["experiment_types"] = [ "RACE" ]
            else
              e["experiment_types"].push "RTPCR"
            end
          else
            e["experiment_types"].push "Sample creation"
            e["types"] = [ "N/A (metadata only)" ]
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

      if 
        protocol_types.find { |pt| pt =~ /hybridization/ } &&
        protocol_types.find { |pt| pt =~ /immunoprecipitation/ }.nil?
        then
        if e["compound"] && e["compound"].find { |compound| compound =~ /sodium chloride/ } then
          e["experiment_types"].push "tiling array: DNA"
        else
          e["experiment_types"].push "tiling array: RNA"
        end
      end

      # annotation = Computational annotation
      if 
        protocol_types.find { |pt| pt =~ /annotation/i } && !e["experiment_types"].include?("RACE") && !e["experiment_types"].include?("RTPCR")
        then
        e["experiment_types"].push "Computational annotation"
        # Also get rid of any reagents, since this really just analyzing old data
        # Juuust kidding
        if false && e["experiment_types"].size == 1 then
          e["strain"] = [ "N/A" ]
          e["tissue"] = [ "N/A" ]
          e["stage"] = [ "N/A" ]
          e["cell_line"] = [ "N/A" ]
          e["antibody_names"] = [ "N/A" ]
          e["antibody_targets"] = [ "N/A" ]
        end
      end

      # If we haven't found a type yet, and there is a growth protocol, then
      # this is probably an RNA Sample creation experiment from Celniker
      if 
        e["experiment_types"].size == 0 && 
          (
            protocol_types.find { |pt| pt =~ /grow/ } || 
            protocol_types.find { |pt| pt =~ /organism_purification_protocol/ }
          )
      then
        e["types"] = [ "N/A (metadata only)" ]
        e["experiment_types"].push "Sample creation"
        e["antibody_names"] = [ "N/A" ]
        e["antibody_targets"] = [ "N/A" ]
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

      # pairwise_sequence_alignment = Alignment
      if e["experiment_types"].size == 0 && protocol_types.find { |pt| pt =~ /pairwise_sequence_alignment/ } then
        if protocol_types.find { |pt| pt =~ /PCR(_amplification)?/ } then
          if e["protocol_types"].find { |row| row["name"] =~ /CAGE/ } then
            # Only way to detect CAGE is by protocol name, since really it's the same kind of experiment
            e["experiment_types"].push "CAGE"
            e["types"] = [ "RNA profiling" ]
          else 
            if e["protocol_types"].find { |row| row["name"] =~ /RNA/ } then
              # These are some poorly characterized Gingeras submissions where the first
              # protocol includes purification, (unlisted) extraction, PCR, and labeling.
              e["experiment_types"].push "RNA-seq"
            elsif e["xschema"] =~ /_712_/ then
              # This experiment looks almost exactly like cDNA sequencing, but is apparently RNA-seq
              e["experiment_types"].push "RNA-seq"
            else
              e["experiment_types"].push "cDNA sequencing"
              e["types"] = [ "gene model" ]
            end
          end
        else
          e["experiment_types"].push "Alignment"
        end
      end

      if e["experiment_types"].include?("ChIP-chip") || e["experiment_types"].include?("ChIP-seq") then
        if e["uniquename"] =~ /replication timing/i then
          e["types"] = [ "replication timing" ]
        elsif e["uniquename"] =~ /origin/i then
          e["types"] = [ "origins of replication" ]
        elsif e["uniquename"] =~ /(orc|mcm)[^a-z]/i then
          e["types"] = [ "replication factors" ]
        end
      end

      # If we have specific types of binding sites, then get rid of the generic
      # "binding sites"
      e["types"].delete("binding sites") if e["types"].include?("chromatin binding sites")
      e["types"].delete("binding sites") if e["types"].include?("chromatin binding site signal data")
      if e["types"].size == 0 && (
        (!e["GSE"].nil? && e["GSE"].length > 0) ||
        e["GSM"].size > 0 ||
        e["sra_ids"].size > 0
      ) then
        e["types"].push "raw sequences"
      end
    }
    print "\n"

    # Search through all of the antibody data to try to find antibody names
    exps.each { |e|
      #antibodies need to have both a target and a name.  this will help distinguish different
      #experiments to the same target.  for example, antibodies to the same protien, but
      #one each for the N- or C-terminus
      e["antibody_names"] = Array.new if e["antibody_names"].nil?
      e["antibody_targets"] = Array.new if e["antibody_targets"].nil?

      e["antibodies"].each { |a|
        # since we are capturing both a target and antibody name, we'll assign both
        #there should always be a worm or fly gene id for an antibody, that should be the "target"
        target = a["attributes"].find { |attr| attr["heading"] == "target id" }
        target = target["value"] unless target.nil?

        #if the target gene id can't be found, then use the target name
        target = a["attributes"].find { |attr| attr["heading"] == "target name" } 
        target = (target.nil? || target["value"] == "Not Applicable") ? nil : target["value"]
        # If not a target name on an antibody, what about a target ID attached to a
        # specimen in this project?  this might be the case for GFP or FLAG
        e["specimens"].each { |sp| 
          target_id = sp["attributes"].find { |attr| attr["heading"] == "target id" || attr["heading"] == "transgene" }
          if target_id then
            target = target_id["value"]
            break
          end
        }
        name = a["attributes"].find { |attr| attr["heading"] == "official name" }
        name = name["value"] unless name.nil?
        
        target.sub!(/(fly|worm)_genes:/, '') unless target.nil?
        e["antibody_names"].push name # unless name.nil? || name.empty?
        e["antibody_targets"].push target # unless target.nil? || target.empty?
      }
      if e["types"].include?("splice sites") ||
        e["types"].include?("transcription/coding junctions") ||
        e["types"].include?("alignments") ||
        e["types"].include?("trace reads") ||
        e["types"].include?("gene models") ||
        e["types"].include?("binding sites") ||
        e["types"].include?("copy number variation") ||
        e["types"].include?("EST alignments") ||
        e["types"].include?("polyA_site") ||
        e["types"].include?("cDNA alignments") then

        e["types"].delete("splice sites")
        e["types"].delete("transcription/coding junctions")
        e["types"].delete("alignments")
        e["types"].delete("trace reads")
        e["types"].delete("gene models")
        e["types"].delete("binding sites")
        e["types"].delete("copy number variation")
        e["types"].delete("EST alignments")
        e["types"].delete("EST alignments")
        e["types"].delete("cDNA alignments")

        if e["types"].include?("signal data") && !e["experiment_types"].include?("Computational annotation") then
          e["types"] = [ "transcription" ]
          e["experiment_types"].push("tiling array: RNA") if e["experiment_types"].delete("ChIP-chip")
        elsif !e["protocol_types"].find { |row| row["type"] =~ /annotation/ } then
          # Piano partial submissions that should be labeled RNA-seq, but only provided the sequences
          if e["experiment_types"].include?("RNA-seq") && !e["protocol_types"].find { |row| row["type"] =~ /alignment/ }  then
            e["types"] = [ "raw sequences" ]
          elsif e["experiment_types"].include?("RACE") || e["experiment_types"].include?("RTPCR") then
            e["types"] = [ "gene model" ]
          elsif e["experiment_types"].include?("Computational annotation")
            e["types"] = [ "gene model" ]
          else
            e["types"] = [ "RNA profiling" ] unless e["types"].find { |t| t =~ /chromatin/ }
          end
        else
          e["types"] = [ "gene model" ]
        end
      elsif e["types"].include?("transcript fragments") then
        e["types"].delete("transcript fragments")
        e["types"] = [ "transcription" ]
        e["experiment_types"].push("tiling array: RNA") if e["experiment_types"].delete("ChIP-chip")
      end
      
      if e["experiment_types"].include?("RNA-seq") then
        # TODO: Do this better: use read lengths to detect transcription
        if e["project"] == "Lai" then
          e["types"] = [ "RNA profiling" ]
        elsif e["project"] == "Celniker" && (e["lab"] == "Gingeras" || e["lab"] == "Brent") then
          e["types"] = [ "transcription" ]
        else
          unless e["types"].include?("raw sequences") then
            e["types"] = [ "RNA profiling" ]
          end
        end
        if e["types"].include?("RNA profiling") && [ "White", "Lieb", "Karpen" ].include?(e["project"]) then
          e["types"] = [ "transcription" ]
        end
      end

      if e["project"] == "MacAlpine" then
        if e["experiment_types"].include?("tiling array: RNA") then
          e["experiment_types"] = [ "tiling array: DNA" ]
          e["types"] = [ "copy number variation" ]
        elsif e["experiment_types"].include?("DNA-seq") then
          e["types"] = [ "copy number variation" ]
        end
      end

      if (e["types"].delete("chromatin binding sites") || e["types"].delete("chromatin binding site signal data")) then
        new_type = "chromatin"
        has_salt = e["compound"] && e["compound"].find { |compound| compound =~ /sodium chloride/ }
        if !(e["antibody_targets"].empty? || e["antibody_targets"].include?("na") || e["antibody_targets"].include?("none")) || has_salt
          e["antibody_targets"].each_index do |i|
            abt = e["antibody_targets"][i]
            abn = e["antibody_names"][i]
            if (new_name = is_histone_antibody(abt) || new_name = is_histone_antibody(abn)) then
              e["antibody_targets"][i] = new_name[0]
              e["antibody_names"][i] = (new_name[1].nil? || new_name[1].empty?) ? new_name[0] : new_name[1]
              e["antibody_targets"].delete_if { |t| t =~ /^His.:/ }
              new_type = "chromatin modification"
            end
            # Consistent formatting:
            if abn =~ /RNA\s*pol.*\s*II/i then
              e["antibody_names"][i] = "RNA polymerase II"
            end
          end
        else
          new_type = "chromatin modification"
        end
        e["types"].push(new_type)
      end

      if e["experiment_types"].include?("tiling array: DNA") && e["types"].include?("signal data") then
        if !e["types"].include?("replication timing") then
          e["types"] = [ "chromatin" ]
        end
      end

      e["antibody_names"].uniq!; e["antibody_names"].compact!
      e["antibody_targets"].uniq!; e["antibody_targets"].compact!

      e["antibody_names"].delete_if { |abname| abname =~ /control/i }
      e["antibody_names"] = e["antibody_names"].map { |abname| ( matches = abname.match(/Ab:([^:]+):/) ).nil? ? abname : matches[1] } # Wiki URL
      e["antibody_names"] = e["antibody_names"].map { |abname| ( matches = abname.match(/elegans\s+(\S+)\s/) ).nil? ? abname : matches[1] } # e.g. "C. elegans DPY-27 1-409 rabbit polyclonal antibody"
      e["antibody_names"] = e["antibody_names"].map { |abname| abname.gsub(/&reg;/, '') } # Who needs registered trademark symbols?
      e["antibody_names"] = e["antibody_names"].map { |abname| abname.gsub(/anti-?/i, '') } # Yes, thanks, it's an antibody
      if e["lab"] == "White" then
        e["antibody_names"] = e["antibody_names"].map { |abname| abname.gsub(/PolII/, 'Covance_8WG16:14861301') } # This has been fixed on the antibody page for future submissions
      elsif e["lab"] == "Snyder" then
        e["antibody_names"] = e["antibody_names"].map { |abname| abname.gsub(/PolII/, 'Covance_8WG16:MMS-126R') } # This has been fixed on the antibody page for future submissions
      end
      e["antibody_targets"] = e["antibody_targets"].map { |abtarget| abtarget.gsub(/Enhanced Green Fluorescent Protein/, 'eGFP') }
      e["antibody_targets"] = e["antibody_targets"].map { |abtarget| (abtarget =~ /^n(\/?)a$/i) ? "none" : abtarget }
      e["antibody_targets"] = [] if ( e["antibody_targets"] == [ "none" ] && e["types"].include?("N/A (metadata only)") )

      # Some cleanup
      e["antibody_targets"].each { |abtarget| abtarget.sub!(/nejire/, 'nej') }
    }

    # Throw out any deprecated or unreleased projects; look up the status in the pipeline
    # database, which is separate from Chado
    # Also, grab creation and release dates
    sth = dbh.prepare("SELECT status, deprecated_project_id, superseded_project_id, created_at, updated_at FROM projects WHERE id = ?")
    sth_release_date = dbh.prepare("SELECT MAX(c.end_time) AS release_date FROM commands c 
                                   INNER JOIN projects p ON p.id = c.project_id 
                                   WHERE c.type = 'Release' AND c.status = 'released' GROUP BY p.id HAVING p.id = ?")
    exps.clone.each { |e|
      pipeline_id = e["xschema"].match(/_(\d+)_/)[1].to_i
      sth.execute(pipeline_id)
      (status, deprecated, superseded, created_at, updated_at) = sth.fetch_array
      if status.nil? then
        # Chado entry, but deleted from pipeline
        exps.delete(e)
        next
      end
      e["status"] = status
      e["deprecated"] = (deprecated != "" && !deprecated.nil?) ? deprecated : false
      e["superseded"] = (superseded != "" && !superseded.nil?) ? superseded : false
      sth_release_date.execute(pipeline_id)
      release_date = sth_release_date.fetch_array
      release_date = release_date.nil? ? updated_at : release_date[0]
      e["created_at"] = Date.parse(created_at).to_s unless created_at.nil?
      e["released_at"] = Date.parse(release_date).to_s unless release_date.nil?
    }
    sth.finish
    sth_release_date.finish

    puts "#{exps.size} total projects"
    #exps.delete_if { |e| (e["status"] != "released" && e["status"] != "approved by user") || e["deprecated"] }
    #puts "#{exps.size} released projects"
    File.open('breakpoint5.dmp', 'w') { |f| Marshal.dump(exps, f) }
  end

  # Get GFF files associated with each experiment
  puts "Collecting GFF files for experiments."
  exps.each { |e|
    e["gff"] = r.collect_gff(e["xschema"]).join(", ")
    print "."; $stdout.flush
  }
  puts ""
  puts "Done."

  # Get microarray information
  puts "Getting microarray size."
  require 'pp'
  exps.each { |e|
    e["array_size"] = e["arrays"].map { |arr|
      arr["attributes"]
    }.map { |array_attrs|
      resolution = array_attrs.find { |a| a["heading"] == "resolution" }
      resolution.nil? ? "" : resolution["value"].sub(/\s*base\s*pairs?|\s*bp/i, 'bp')
    }.uniq
    e["array_platform"] = e["arrays"].map { |arr|
      arr["attributes"]
    }.map { |array_attrs|
      platform = array_attrs.find { |a| a["heading"] == "platform" }
      platform.nil? ? "" : platform["value"]
    }.uniq
  }
  puts "Done."

  puts "Collecting SAM files for experiments."
  exps.each { |e|
    e["sam"] = r.collect_sam(e["xschema"]).join(", ")
    print "."; $stdout.flush
  }
  puts ""
  puts "Done."

  # Get feature counts for CAGE or cDNA sequencing experiments
  puts "Getting sequence counts"
  exps.each { |e|
    if e["experiment_types"].include?("CAGE") then
      # Line count of SAM file
      e["sequence_count"] = 0
      e["sam"].each { |sam_file|
        puts "Found SAM #{sam_file} for #{e["xschema"]}"
        project_id = e["xschema"].match(/_(\d+)_/)[1].to_i
        sam_file_path = File.join("/modencode/raw/data/", project_id.to_s, "extracted", sam_file)
        cmd = "cat #{Escape::shell_command(sam_file_path)} | grep -v '^@' | wc -l"
        cmd = "z" + cmd if sam_file_path =~ /\.gz$/
        e["sequence_count"] += `#{cmd}`.chomp.to_i
        puts "Got #{e["sequence_count"]} sequences for #{e["xschema"]}"
      }
    end
    if e["experiment_types"].include?("cDNA sequencing") then
      # Number of cDNA features
      sequences = r.get_number_of_features_of_type(e["xschema"], "cDNA")
      e["sequence_count"] = sequences if sequences && sequences != 0
      puts "Got #{e["sequence_count"]} sequences for #{e["xschema"]}"
    end
  }
  puts "Done."

  # Get any projects that aren't in Chado yet
  chado_ids = exps.map { |e| e["xschema"].match(/_(\d+)_/)[1].to_i }

  sth = dbh.prepare("SELECT id, name, status, pi, lab, created_at, deprecated_project_id, superseded_project_id FROM projects")
  sth.execute()
  sth.fetch_all.each { |row|
    next if chado_ids.include?(row["id"].to_i)
    new_exp = {
      "xschema" => "modencode_experiment_#{row["id"]}_data",
      "uniquename" => row["name"],
      "status" => row["status"],
      "project" => row["pi"].split(/,/)[0],
      "lab" => row["lab"].split(/,/)[0],
      "created_at" => Date.parse(row["created_at"].to_s).to_s,
      "deprecated" => (row["deprecated_project_id"] != "" && !row["deprecated_project_id"].nil?) ? row["deprecated_project_id"] : false,
      "superseded" => (row["superseded_project_id"] != "" && !row["superseded_project_id"].nil?) ? row["superseded_project_id"] : false,
      "released_at" => "",
      "organisms" => [],
      "types" => [],
      "experiment_types" => [],
      "tissue" => [],
      "strain" => [],
      "cell_line" => [],
      "stage" => [],
      "antibody_names" => [],
      "antibody_targets" => [],
      "compound" => [],
      "array_platform" => [],
      "growth_condition" => [],
      "dnase_treatment" => [],
      "array_size" => [],
      "array_platform" => [],
      "rna_ids" => [],
      "rnai_targets" => []
    }
    exps.push(new_exp)
  }
  sth.finish
  dbh.disconnect

  puts "Trying to figure out project versions"
  exps.each { |e|
    version = 1
    project_id = e["xschema"].match(/_(\d+)_/)[1].to_i
    loop do
      deprecates = exps.find { |e2| e2["deprecated"] == project_id || e2["superseded"] == project_id }
      break unless deprecates
      project_id = deprecates["xschema"].match(/_(\d+)_/)[1].to_i
      version += 1
    end
    if version != 1 then
    end
    e["version"] = version unless version == 1
  }
  puts "Done."

  puts "Trying to find the reaction count for RACE/RTPCR experiments."
  exps.each { |e|
    next unless e["experiment_types"].include?("RACE") || e["experiment_types"].include?("RTPCR")
    reactions = r.get_number_of_features_of_type(e["xschema"], "mRNA")
    if (
      !reactions || reactions.to_i == 0 ||
      e["project"] == "Piano" # Piano submission(s?) find the genes post-experiment, so we do want ESTs
    ) then
      reactions = r.get_number_of_features_of_type(e["xschema"], "EST")
    end
    e["reactions"] = reactions
    if e["project"] == "Waterston" && e["lab"] == "Green" then
      # Get the intron counts, too
      introns = r.get_number_of_features_of_type(e["xschema"], "intron")
      e["features"] = introns
    end
    if (reactions.to_i > 10000) then
      # Probably a Celniker RACE-seq experiment
      e["reactions"] = r.get_number_of_data_of_type(e["xschema"], "transcript")
    end
  }
  puts "Done."

  # Copy over missing info to deprecated experiment
  exps.each { |e|
    if e["experiment_types"].size == 0 && e["deprecated"] then
      deprecator = e
      while deprecator["deprecated"] || deprecator["superseded"] do
        deprecator = exps.find { |exp|
          deprecator_id = deprecator["deprecated"] || deprecator["superseded"]
          exp["xschema"] == "modencode_experiment_#{deprecator_id}_data"
        }
      end
      deprecator.each_key { |k|
        next if (k == "superseded" || k == "deprecated")
        if e[k].nil? || ((e[k].is_a?(String) || e[k].is_a?(Array)) && e[k].empty?) then
          e[k] = deprecator[k]
        end
      }
    end
  }

  File.open('breakpoint6.dmp', 'w') { |f| Marshal.dump(exps, f) }

end

# Get replicate count
exps.each { |e|
  e["replicates"] = nil

  if e["all_data"].nil? 
   if e["released_at"] == "" then #|| e["deprecated"] then
     e["replicates"] = "NOT RELEASED"
     next
   else
     puts e["xschema"]
     puts "  NO DATA"
     exit
   end
  end

  # *extract*
  extracts = e["all_data"].find_all { |d| d["heading"] =~ /extract\b/i || d["name"] =~ /extract\b/i }.reject { |d| d["value"] == nil || d["value"].empty? }
  reps = 0
  extracts.uniq_by { |d| [ d["heading"], d["name"] ] }.map { |d| [ d["heading"], d["name"] ] }.each { |unq|
    unq = extracts.find_all { |d| d["heading"] == unq[0] && d["name"] == unq[1] }.map { |d| d["value"].sub(/ (Nucleosomes|Pull-down|Input)/, '').sub(/^(Extract|Control)\d$/, '\1').sub(/(_GEL|_BULK)$/, '') }.uniq.compact.size
    reps = [reps, unq].max
  }
#  reps = extracts.map { |d| d["value"].sub(/ (Nucleosomes|Pull-down|Input)/, '').sub(/^(Extract|Control)\d$/, '\1').sub(/(_GEL|_BULK)$/, '') }.uniq.compact.size
  e["replicates"] = reps if reps > 0

  # Sample Name
  samples = Array.new
  if e["replicates"].nil? then
    samples = e["all_data"].find_all { |d| d["heading"] =~ /Sample\s*Names?/i }
    if !samples.find { |s| s["attributes"] } then
      # Didn't get them earlier
      samples.each { |s| attrs = r.get_attributes_for_datum(s["data_id"], e["xschema"]); s["attributes"] = attrs }
    end
    if samples.find { |s| s["attributes"] && s["attributes"].find { |a| a["name"] =~ /replicate set/ } } then
      samples = samples.map { |s| s["attributes"].find { |a| a["name"] =~ /replicate set/ } }
    end
    reps = samples.map { |d| d["value"].sub(/\d.of.\d_rep/, 'rep').sub(/\d[_-]\d[_-](\d)$/, '\1').sub(/(Input|ChipSeq)_(\d)/i, '\2') }.uniq.compact.size
    e["replicates"] = reps if reps > 0
  end

  # Oliver submissions that are really just 1 replicate, prolly
  if e["project"] == "Oliver" && e["all_data"].find { |d| d["heading"] =~ /Parameter\s*Values?/i && d["name"] =~ /pipeline version/i } then
    stages = e["all_data"].find_all { |d| d["heading"] =~ /(Parameter|Result)\s*Values?/i && d["name"] =~ /stage/i }
    if stages.size > 0 then
      reps = 0
      stages.each { |d|
        pool_count = r.get_applied_protocol_data_count(d["heading"], d["name"], e["xschema"])
        reps = [ pool_count, reps ].max
      }
      e["replicates"] = reps if reps > 0
    end
  end


  # explicit pool values
  ## 2501 has Result Value [pool] as the only divider
  if e["replicates"].nil? then
    special = e["all_data"].find_all { |d| d["heading"] =~ /(Parameter|Result)\s*Values?/i && d["name"] =~ /pool/i }
    if special.size > 0 then
      reps = 0
      special.each { |d|
        pool_count = r.get_applied_protocol_data_count(d["heading"], d["name"], e["xschema"])
        reps = [ pool_count, reps ].max
      }
      e["replicates"] = reps if reps > 0
    end
  end

  # Result File
  if e["replicates"].nil? then
    results = e["all_data"].find_all { |d| d["heading"] =~ /Result\s*Files?/i }
    if results.size > 0 then
      uniq_heading_and_name = results.uniq_by { |d| [ d["heading"], d["name"] ] }.map { |d| [ d["heading"], d["name"] ] }
      reps = nil
      uniq_heading_and_name.each { |hn|
        count = results.find_all { |d| d["heading"] == hn[0] && d["name"] == hn[1] }.map { |d| d["value"] }.uniq.compact.size
        reps = reps.nil? ? count : [ reps, count ].min
      }
      e["replicates"] = reps if reps > 0
    end
  end

  # GEO ID
  if e["replicates"].nil? then
    geoids = e["all_data"].find_all { |d| d["name"] =~ /GEO/i }
    reps = geoids.map { |d| d["value"] }.uniq.compact.size
    e["replicates"] = reps if reps > 0
  end


  e["replicates"] = "COMPUTATIONAL ANNOTATION" if e["experiment_types"].include?("Computational annotation")
  e["replicates"] = "SAMPLE CREATION" if e["experiment_types"].find { |t| t =~ /Sample creation/i }

  if (e["replicates"].nil? || e["replicates"] == 0 || e["replicates"] == "MISSING") then
    puts e["xschema"]
    puts "  No replicate info!"
    puts e["experiment_types"].pretty_inspect
    puts e["all_data"].map { |d| "#{d["heading"]} [#{d["name"]}] = #{d["value"]}" }.pretty_inspect
    exit
  end
}





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

