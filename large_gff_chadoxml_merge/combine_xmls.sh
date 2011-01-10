#!/bin/bash
head -n -1 out_003_nolocs_noprops_noanalysis.tmp > bad_cvterms_2934.chadoxml
cat out_006_final.xml >> bad_cvterms_2934.chadoxml
echo "</chadoxml>" >> bad_cvterms_2934.chadoxml
