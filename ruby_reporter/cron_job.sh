#!/bin/bash

today=`date "+%Y-%m-%d"`
filename="/modencode/raw/tools/reporter/output/output_nih_${today}.txt"
dmel_filename="/modencode/raw/tools/reporter/output/dmelanogaster_${today}.txt"
cele_filename="/modencode/raw/tools/reporter/output/celegans_${today}.txt"
amazon_filename="/modencode/raw/tools/reporter/output/amazon_tagging_${today}.txt"
logfile="/modencode/raw/tools/reporter/output/logfile_${today}.txt"

echo "***************************  MAKE NIH REPORT  ************************************"
time GEM_HOME=/var/www/gems/ /modencode/raw/tools/reporter/make_report.rb csv_nih "$filename" >>"$logfile" 2>&1


head -n 1 "$filename" > "$dmel_filename"
head -n 1 "$filename" > "$cele_filename"
awk 'BEGIN { FS="\t"; getline; col = 0; for (i = 1; i <= NF; i++) { if ($i == "Organism") { col = i } } } { if ($col ~ /Drosophila melanogaster/) { print $0 }  }' "$filename" >> "$dmel_filename"
awk 'BEGIN { FS="\t"; getline; col = 0; for (i = 1; i <= NF; i++) { if ($i == "Organism") { col = i } } } { if ($col ~ /Caenorhabditis elegans/) { print $0 }  }' "$filename" >> "$cele_filename"

echo "**************************  MAKE AMAZON REPORT  **********************************"
time GEM_HOME=/var/www/gems/ /modencode/raw/tools/reporter/make_report.rb amazon_tagging "$amazon_filename" -b >>"$logfile" 2>&1

echo "*****************************  MOVE FILES  ***************************************"
mkdir -v /modencode/raw/tools/reporter/bps.$today >>"$logfile" 2>&1
mv -v /modencode/raw/tools/reporter/breakpoint*.dmp /modencode/raw/tools/reporter/bps.$today/ >>"$logfile" 2>&1

echo "Logs for this cron can be found in ${logfile}"
echo "******************************  FINISHED  ****************************************"
