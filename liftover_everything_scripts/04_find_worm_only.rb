#!/usr/bin/ruby

report = Dir.glob("/modencode/raw/tools/reporter/output/celegans_*.csv").sort.last

ok_ids = Hash.new
File.open(report, "r") { |f|
  header = f.readline
  id_idx = header.split(/\t/).find_index("Submission ID")
  f.each { |line|
    submission_id = line.split(/\t/)[id_idx].sub(/ .*/, '')
    ok_ids[submission_id] = true
  }
}

File.open("03_sorted_by_type.txt") { |f|
  File.open("04_worm_only.txt", "w") { |out|
    f.each { |line|
      submission_id = line.match(/\/modencode\/raw\/data\/(\d+)\//)
      next unless submission_id
      out.puts line if (ok_ids[submission_id[1]])
    }
  }
}
