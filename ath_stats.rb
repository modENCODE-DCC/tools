#!/usr/bin/ruby

require 'rubygems'
require '/srv/www/pipeline/submit/config/environment'

BASE_URL = "http://heartbroken.lbl.gov/athena_balancer"

host = `hostname`.chomp

def get_stats(host)
  stat_cpu = `vmstat 1 2 | tail -1 | awk '{ print 100 - $15; }'`.chomp
  stat_mem = `awk '{ if ($1 == "MemTotal:") TOTAL = $2 } { if ($1 == "MemFree:") FREE = $2 } END { print 100-(FREE / TOTAL)*100 }' /proc/meminfo`.chomp
  # jobs_running * 10 to give it more weight
  jobs_running = Command.find_all_by_host(host).find_all { |cmd| Project::Status::is_active_state(cmd.status) }.size*10
  stat_str = "c=#{stat_cpu},m=#{stat_mem},0cus=#{jobs_running}"
end

def send_update(host, stat_str)
  get_cmd = "wget -O - -q --timeout=10 #{BASE_URL}/update/phys?h=#{host},#{stat_str}"
  system(get_cmd)
end

send_update(host, get_stats(host))
