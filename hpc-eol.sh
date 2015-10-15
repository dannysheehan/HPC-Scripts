#!/bin/bash
# -----------------------------------------------------
# adjust wall time leading up to stopping HPC running jobs
# -----------------------------------------------------

DDAY_STR="Sun Jun 30 2015 22:00:00"

now=$(date  +%s)
dday=$(date -d "$DDAY_STR" +%s)
sec_rem=$(($dday - $now))

hours=$(($sec_rem / 3600))

wall_time="$hours:00:00"



# 231:00:00
echo $wall_time

qselect -s Q -l walltime.gt.$wall_time | \
while read job
do 
  echo "qalter $job"
  qalter -l "walltime=$wall_time" $job
done

echo "set server resources_max.walltime = $wall_time"
qmgr -c "set server resources_max.walltime = $wall_time"

