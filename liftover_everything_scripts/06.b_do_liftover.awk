#!/usr/bin/awk -f

BEGIN {
  # TODO: Figure out FROM build
  to_build = "ws220"
  base="/modencode/raw/data/"
  base_re=base; gsub(/\//, "\\/", base_re)
  new_base = "/modencode/raw/tmp/lifted/"
}
{
  type=$1
  from_build=$2
  abs_file=$3

  file = abs_file; sub(base_re, "", file)
  filename = substr(file, match(file, /[^\/]+$/), length(file))
  path = substr(file, 0, match(file, /[^\/]+$/)-1)

  project_id = substr(path, 0, match(path, /\//)-1)
  suffix = substr(path, match(path, /\/extracted\//)+length("/extracted/"), length(path))
  lift_dir = from_build "/" suffix
  abs_lift_dir = base project_id "/extracted/" lift_dir
  abs_lift_dir = new_base project_id "/extracted/" lift_dir
  #system("mkdir -p \"" abs_lift_dir "\"")
  if (type == "BAM") {
    flag = "--sam"
  } else if (type == "SAM") {
    flag = "--sam"
  } else if (type == "GFF") {
    flag = "--gff"
  } else if (type == "WIG") {
    flag = "--wig"
  } else if (type == "XML") {
    flag = "--xml"
  } else {
    print "Unknown type: " type
    exit
  }

  lift_cmd = "java -jar liftover.jar " flag " \"" abs_file "\" -1 " from_build " -2 " to_build " -o \"" abs_lift_dir filename "\""
  print lift_cmd
}
