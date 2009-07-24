#!/bin/bash

echo "rsyncing data....."
rsync -u -i --delete  --filter '+ /[0-9]*/browser' --filter '- /*/*' --stats --compress --recursive --times -m oicr_sync@heartbroken.lbl.gov::modENCODE_GBrowse /srv/gbrowse/gbrowse/modencode_preview/original_structure/

echo "removing old/broken symlinks and conf files....."
find /srv/gbrowse/gbrowse/modencode_preview/data -type l -exec sh -c "[ -e {} ] || rm {}" \;

rm /srv/gbrowse/gbrowse/modencode_preview/conf/[0-9]*.conf

for project_dir in /srv/gbrowse/gbrowse/modencode_preview/original_structure/*/browser; do
  echo "------------------------------------------------------------"
  echo "PROCESSING $project_dir"
  /srv/gbrowse/gbrowse/modencode_preview/update.pl $project_dir
done

