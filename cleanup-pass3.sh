#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :cleanup-pass1.sh
#description    :Final phase of cleanup process where we do the actual file deletion, but only if users have not accessed their files since.
#author         :Danny W Sheehan
#date           :July 2014
#website        :www.setuptips.com
#---------------------------------------------------------------------------
# The filesystem we are performing housekeeping (cleanup) on.
FS_NAME="/scratch365"

# Just for testing
FS_NAME="/home/$USER"

LAST_ACCESS=365

# The directory in which the files to delete list and exceptions are kept.
CLEANUP_HOME="${FS_NAME}/CLEANUP"

TEMP_EXCEPT="/tmp/dskskjej$$"

THIS_HOST=`uname -n`


# NOTE: Best to do deletion on NFS server rather than head node or NFS client.
# It's more efficient that doing this over the network.
NFS_SERVER="barrine"
if [ "${THIS_HOST}" == "${THIS_HOST#${NFS_SERVER}}" ]
then
  echo "ERROR: $0 can only run on $NFS_SERVER" >&2
  exit 1
fi

# comment out for exra checks for NFS server
#if [ -z "$(/bin/df|/bin/grep ${FS_NAME})" ]
#then
#  echo "ERROR: $0 can only run on NFS server active node" >&2
#  exit 2
#fi


cd $CLEANUP_HOME

if [ ! -f "delete-exceptions.txt" ]
then
  echo "ERROR: $0 delete-exceptions.txt file missing" >&2
  exit 3
fi


if [ ! -f "delete-filelist.txt" ]
then
  echo "ERROR: $0 delete-filelist.txt file missing" >&2
  exit 4
fi

#
# remove blank lines and comments from delete exceptions.
#
sed -e "/^[ \t]*$/d" -e "/^#/d" delete-exceptions.txt > $TEMP_EXCEPT

grep -z -v -f $TEMP_EXCEPT delete-filelist.txt | xargs -l1 -0 | while read f
do
    if [ -e "$f" ]
    then
      DAYS_LAST_MOD=$(( ( $(date +"%s") - $(stat -c "%Y" "$f") ) / 86400 ))
      DAYS_LAST_ACCESS=$(( ( $(date +"%s") - $(stat -c "%X" "$f") ) / 86400 ))
      if [ $DAYS_LAST_ACCESS -gt $LAST_ACCESS ]
      then
        ls -lud "$f"
        # uncomment
        rm "$f"
      fi
    fi
done > deleted-filelist.txt

rm -f $TEMP_EXCEPT
