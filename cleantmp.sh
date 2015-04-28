#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :cleantmp.sh
#description    :cleans files in /tmp that are not open and only if the
#               owner has no processes running at all on the machine.
#               It will echo the name of the user and the output "removed"
#               if it removes a file or directory.
#               NOTE: The fuser is a bit redudant i agree.
#author         :Danny W Sheehan
#date           :April 2015
#
#  Usage: $0 <volume>
#---------------------------------------------------------------------------
# not accessed within the last $RESHNESS days
FRESHNESS=2
find /tmp -type f -atime +${FRESHNESS} -print0 | \
    while IFS= read -r -d '' FILEN
do 
  ( fuser "$FILEN" > /dev/null || \
    pgrep -u `stat -c %U "$FILEN"` > /dev/null ) || \
  ( stat -c %U "$FILEN" && rm -fr "$FILEN" && echo Removed $FILEN ) 
done
