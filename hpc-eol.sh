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

echo "set server resources_max.walltime = $wall_time"
# qmgr -c "set server resources_max.walltime = $wall_time"

echo "set server resources_default.walltime = $wall_time"
# qmgr -c "set server resources_default.walltime = $wall_time"
#
# Add queue with wall times here
#
echo "set queue workq resources_max.walltime = $wall_time"
#qmgr -c "set queue workq resources_max.walltime = $wall_time"

echo "set queue fast resources_max.walltime = $wall_time"
#qmgr -c "set queue fast resources_max.walltime = $wall_time"

echo "set queue urgent resources_max.walltime = $wall_time"
#qmgr -c "set queue urgent resources_max.walltime = $wall_time"

# snapshot
#qmgr -c "set queue backfill resources_max.walltime = 02:00:00
#qmgr -c "set queue support resources_max.walltime = 72:00:00
#qmgr -c "set queue testq resources_max.walltime = 02:00:00
#qmgr -c "set queue interact resources_max.walltime = 06:00:00
#qmgr -c "set queue fast resources_max.walltime = 168:00:00
#qmgr -c "set queue ebi resources_max.walltime = 24:00:00
####qmgr -c "set queue urgent resources_max.walltime = 168:00:00
###qmgr -c "set queue workq resources_max.walltime = 336:00:00
###qmgr -c "set server resources_default.walltime = 168:00:00
###qmgr -c "set server resources_max.walltime = 240:00:00
