#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :cleantmp.sh
#description    :cleans files in /tmp that 
#               a) have not been accessed in $FRESHNESS days
#               b) are not currently open by a process
#               c) owner has processes running
#
#               I agree, b) and c) are redundant. 
#
#               It will echo the name of the user and the output "removed"
#               if it removes a file or directory.
#
#author         :Danny W Sheehan
#date           :April 2015
#
#  Usage: $0 
#---------------------------------------------------------------------------
# not accessed within the last $RESHNESS days
FRESHNESS=2
find /tmp -type f -atime +${FRESHNESS} -print0 | \
    while IFS= read -r -d '' FILEN
do 
  ( fuser "$FILEN" > /dev/null || \
    pgrep -u `stat -c %U "$FILEN"` > /dev/null ) || \
  ( stat -c %U "$FILEN" && rm -f "$FILEN" && echo Removed $FILEN ) 
done
