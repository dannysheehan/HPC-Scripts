#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :apan_du.sh
#description    :a wrapper for pan_du that also identifies directories with 
#               too many files for PANASAS to handle efficiently.
#               It does a `find` first to identify these directories before
#               running a pan_du.
#author         :Danny W Sheehan
#date           :April 2015
#
#  Usage: $0 <volume>
#---------------------------------------------------------------------------
MAXDIRFILESLIMIT=3000
MAXFILESLIMIT=300000


DDIR=$1

if [ ! -n "$DDIR" -o ! -d "$DDIR" -o -h "$DDIR" ]
then
  echo "ERROR: $DDIR must be a directory and not a symbolic link" >&2
  exit 1
fi

PANDU_DIR="$DDIR/.apandu"
mkdir -p $PANDU_DIR

SKIPDIRSFILE="$PANDU_DIR/skip.txt"

PANDU_OUT="$PANDU_DIR/PanasasUsageReport_$(date +%F).csv"
PANDU_ERR="$PANDU_DIR/PanasasUsageReport_$(date +%F).ER"

if [ ! -e "$PANDU_OUT" ]
then
  echo "# UserName,DefaultGroup,Filesystem,GBytes,Files,kB/file,RunTime" > $PANDU_OUT
  date > $PANDU_ERR
fi

touch $PANDU_OUT
touch $PANDU_ERR

FINDFILES="$PANDU_DIR/find.out"

for d in `ls -1u $DDIR`
do

  if [ ! -d "$DDIR/$d" ]
  then
    continue
  fi

  # dereference if symbolic link
  DPATH=$(readlink -f "$DDIR/$d")

  # Don't redo work we have already done.
  if  grep -Fq ",${DPATH}," $PANDU_OUT
  then
    continue
  fi

  USERN=$(stat -L -c '%U' "$DPATH")
  USERG=$(stat -L -c '%G' "$DPATH")

  START_TIME=$(date -d "now" "+%s")

  # Allows the ability to skip files.
  if [ -f "$SKIPDIRSFILE" -a -s "$SKIPDIRSFILE" ]  && \
     grep -F "$DPATH" $SKIPDIRSFILE
  then
    echo "$DPATH:$USERN:$USERG: skipped in $SKIPDIRSFILE" >>  $PANDU_ERR
    continue
  fi

  find  "$DPATH" -noleaf -type f > $FINDFILES
  NUMFILES=`cat $FINDFILES | wc -l`

  if [ -n "$NUMFILES" ] && [ $NUMFILES -gt $MAXFILESLIMIT ]
  then
    echo "$DPATH:$USERN:$USERG: $NUMFILES files exceeds $MAXFILESLIMIT total file limit"  >>  $PANDU_ERR
    echo "$DPATH:$USERN:$USERG:$NUMFILES:MAXFILESLIMIT ($MAXFILESLIMIT) exceeded" >> $PANDU_ERR

    mv ${FINDFILES} "${PANDU_DIR}/${d}.files"
    continue
  fi

  DIRSORT=`sed -e "s/[^\/]*$//" $FINDFILES | sort | uniq -c | sort -n | tail -1`
  DIRMAXFILES=`echo $DIRSORT | awk '{print $1}'`
  DIRNAME=`echo $DIRSORT | awk '{print $2}'`
  if [ -n "$DIRMAXFILES" ] && [ $DIRMAXFILES -gt $MAXDIRFILESLIMIT ]
  then
      echo "$DPATH:$USERN:$USERG:$DIRMAXFILES:$DIRNAME:MAXDIRFILESLIMIT ($MAXDIRFILESLIMIT) exceeded" >> $PANDU_ERR
    mv ${FINDFILES} "${PANDU_DIR}/${d}.files"
    continue
  fi

  # dir /home/uqdshee2: 5494 files, 1227024 KiB
  PANDUDATA=$(pan_du -s -t 4  "$DPATH" 2>>  $PANDU_ERR)
  if [ $? != 0 ]
  then
    echo "ERROR - problem with pan_du see $PANDU_ERR"
    exit 1
  fi

  NFILES=$(echo $PANDUDATA | awk '{print $3}')
  KBYTES=$(echo $PANDUDATA | awk '{print $5}')
  GBYTES=$(( $KBYTES / 1024 / 1024 ))
  
  KBFILE="0"
  if [ -n "$NFILES" -a $NFILES -gt 0 ]
  then
    KBFILE=$(( $KBYTES / $NFILES ))
  fi

  END_TIME=$(date -d "now" "+%s")
  TIMEMIN=$(( ( $END_TIME - $START_TIME ) / 60 ))
  
  
  # UserName,DefaultGroup,Filesystem,GBytes,Files,kB/file,RunTime
  echo "$USERN,$USERG,$DPATH,$GBYTES,$NFILES,$KBFILE,$TIMEMIN" >> $PANDU_OUT

done 

date >> $PANDU_ERR
