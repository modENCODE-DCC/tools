#!/bin/bash

grep -e "/extracted/\|/tracks/" all_files.txt | grep -v '/[Ww][Ss][0-9][0-9][0-9]/' | grep -v '/[Ww][Ss][0-9][0-9][0-9]$' | grep -v '.broken$' > 01_extracted_and_tracks.txt

