#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :cleanup-pass1.sh
#description    :Identifies files owned by users that have not changed in $LAST_ACCESS days as part of a 3 phase cleanup process that involves notifying users.
#author         :Danny W Sheehan
#date           :July 2014
#website        :www.setuptips.com
#
#---------------------------------------------------------------------------

# The filesystem we are performing housekeeping (cleanup) on.
FS_NAME="/scratch365"

# Just for testing
FS_NAME="/home/$USER"

# The age of the files to cleanup.
LAST_ACCESS=30

# The directory in which the files to delete list and exceptions are kept.
CLEANUP_HOME="${FS_NAME}/CLEANUP"

if [ ! -e "$CLEANUP_HOME" ]
then
  mkdir $CLEANUP_HOME
fi


# The node this script is meant to run on. Safety measure.
HEAD_NODE="barrine"

THIS_HOST=`uname -n`
if [ "${THIS_HOST}" == "${THIS_HOST#${HEAD_NODE}}" ]
then
  echo "ERROR: $0 can only run on a $HEAD_NODE node"
  exit 0
fi

cd $CLEANUP_HOME

# Keep a backup of the old list of files that were deleted.
# This is a useful audit for people who complain about their files missing.
if [ -e "delete-filelist.txt" ]
then
  mv delete-filelist.txt delete-filelist.`date +"%Y%m"`
fi

# Find old files that have not been accessed in $AGE days
find $FS_NAME -atime +$LAST_ACCESS -type f -print0  > delete-filelist.txt
