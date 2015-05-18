#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :volfillrate.sh
#description    :rough script to determine how quickly a volume is filling.
#               and how much time you have before it is full.
#author         :Danny W Sheehan
#date           :April 2015
#
#  Usage: $0 <volume>
#---------------------------------------------------------------------------


FS_MOUNT=$1
SAMPLE_INTERVAL=60

takesample()
{
  BEFORE_USAGE=`df -k -P $FS_MOUNT | tail -1 | awk '{print $3}'`
  sleep $SAMPLE_INTERVAL
  AFTER_USAGE=`df -k -P $FS_MOUNT | tail -1 | awk '{print $3}'`

  if [ $AFTER_USAGE -eq $BEFORE_USAGE ]
  then
    echo -n "."
  else
    echo
    AVAILABLE=`df -k -P $FS_MOUNT | tail -1 | awk '{print $4}'`
    FILLRATE=`echo "scale=2;($AFTER_USAGE - $BEFORE_USAGE) / 1024 / $SAMPLE_INTERVAL" | bc -l`
    FULLIN=`echo "scale=2;$AVAILABLE / ($AFTER_USAGE - $BEFORE_USAGE) * $SAMPLE_INTERVAL / 60 / 60 / 24" | bc -l`
    MEMFREE=$(( $AVAILABLE / 1024 ))
    echo "$FILLRATE Mbytes/Sec, $MEMFREE Mbytes free,  Full in  $FULLIN days"
  fi
}


while true
do
  takesample
done
