#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :apan_du.sh
#description    :a wrapper for pan_du that idenfies directories with too many
#               files for PANASAS to handle efficiently.
#               It does a `find` first to identify these directories before
#               running a pan_du.
#author         :Danny W Sheehan
#date           :April 2015
#
#  Usage: $0 <volume>
#
#---------------------------------------------------------------------------
MAXPANFILES=2000
MAXPANTOTAL=300000


DDIR=$1

if [ ! -n "$DDIR" -o ! -d "$DDIR" -o -h "$DDIR" ]
then
  echo "ERROR: $DDIR must be a directory and not a symbolic link" >&2
  exit 1
fi

PANDU_DIR="$DDIR/.apandu"
mkdir -p $PANDU_DIR

SKIPDIRSFILE="$PANDU_DIR/skip.txt"

PANDU_OUT=$PANDU_DIR/$(date +%Y%m%d)
#touch $PANDU_OUT
cat /dev/null > $PANDU_OUT

FINDFILES="$PANDU_DIR/find.out"

for d in `ls -1u $DDIR`
do
  if [ ! -d "$DDIR/$d" ]
  then
    continue
  fi

  # Don't redo work we have already done.
  if  grep -Fq "dir ${DDIR}/${d}:" $PANDU_OUT
  then
    continue
  fi

  # Allows the ability to skip files.
  if [ -f "$SKIPDIRSFILE" -a -s "$SKIPDIRSFILE" ]  && \
     grep -F "$DDIR/$d" $SKIPDIRSFILE
  then
    echo "dir $DDIR/$d: -1 files, ERROR SKIP"
    continue
  fi

  find  "$DDIR/$d" -noleaf -type f > $FINDFILES
  NUMFILES=`cat $FINDFILES | wc -l`

  if [ -n "$NUMFILES" ] && [ $NUMFILES -gt $MAXPANTOTAL ]
  then
    echo "dir $DDIR/$d: $NUMFILES files, ERROR "
    mv ${FINDFILES} "${PANDU_DIR}/${d}.files"
    continue
  fi

  DIRSORT=`sed -e "s/[^\/]*$//" $FINDFILES | sort | uniq -c | sort -n | tail -1`
  DIRMAXFILES=`echo $DIRSORT | awk '{print $1}'`
  if [ -n "$DIRMAXFILES" ] && [ $DIRMAXFILES -gt $MAXPANFILES ]
  then
    echo "dir $DDIR/$d: $NUMFILES files, ERROR $DIRSORT"
    mv ${FINDFILES} "${PANDU_DIR}/${d}.files"
    continue
  fi

  # dir /home/uqdshee2: 5494 files, 1227024 KiB
  pan_du -s -t 4  $DDIR/$d
done >> $PANDU_OUT
