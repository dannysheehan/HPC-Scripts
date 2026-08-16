#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :lsdircount.sh
#description    :
#author         :Danny W Sheehan
#date           :April 2015
#
#  Usage: $0 <volume> 
#---------------------------------------------------------------------------

MAXDIRFILESLIMIT=3000

DDIR=$1

if [ ! -n "$DDIR" -o ! -d "$DDIR" -o -h "$DDIR" ]
then
  echo "ERROR: $DDIR must be a directory and not a symbolic link" >&2
  exit 1
fi

APANPATH="$DDIR/.apandu"

RDATE=`date -d date -d yesterday +%Y-%m-%d`
ERR_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.ER"

if [ ! -e "$ERR_FILE" ]
then
  RDATE=`date -d date -d today +%Y-%m-%d`
  ERR_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.ER"
  if [ ! -e "$ERR_FILE" ]
  then
    echo "ERROR: apan_du.sh has not been run the last day or two" >&2
    exit 1
  fi
fi

if ! grep -q "^END:" "$ERR_FILE"
then
  echo "ERROR: apan_du.sh has not finished running or was terminated." >&2
  exit 1
fi

FINDFILES="$APANPATH/$USER.files"
if [ ! -e "$FINDFILES" ]
then
  echo "we are cool you have no $DDIR quota violations"
  exit 0
fi

sed -e "s/[^\/]*$//" $FINDFILES | sort | uniq -c | sort -rn |\
while read DIRSORT 
do
  DIRMAXFILES=`echo $DIRSORT | awk '{print $1}'`
  DIRNAME=`echo $DIRSORT | awk '{print $2}'`
  if [ -n "$DIRMAXFILES" ] && [ $DIRMAXFILES -gt $MAXDIRFILESLIMIT ]
  then
    echo "$DIRMAXFILES  $DIRNAME"
  fi
done
