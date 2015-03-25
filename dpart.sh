#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :dpart.sh
#description    :A wrapper for fpart that chunks based on directories
#author         :Danny W Sheehan
#date           :March 2015
# This script uses fpart and chunks directories based on a minimum CHUNKZIZE
# specified in kBytes. 
#
#  Usage: $0 [-s <chunk_size_kbytes>] [-o <part_dir> ] <directory_to_partition> " >&2
#
# -------------------------------------------------------------------------------
export PATH=$PATH:/usr/local/bin:/sw/fpart/0.9.2/bin/

DU="dmdu"


# 20 GiByte default chunk size
CHUNKSIZE=$((20*1024*1024))

FPARTBYTES=$((2*$CHUNKSIZE*1024))


# ---------
findleaves() {
  maxdirsize=0
  maxdir=""
  while read -r line
  do
    dirname=`echo "$line" | awk  -F $'\t' '{print $3}'`
    if ! grep -q -F "$dirname/" $DATFILE  > /dev/null
    then
      chunksize=`echo "$line" | awk  -F $'\t' '{print $2}'`
      if [ $chunksize -gt $maxdirsize ]
      then
        maxdirsize=$chunksize
        maxdir=$dirname
      fi
    fi
  done <  $DATFILE 

  echo  "$chunksize"
}

# ---------
partition() {
  level=$1
  index=$2
  dirname="$3"

  local chunk=`printf "chunk-%d-%d\n" $level $index`

  echo "partition $level $index $dirname"

  #
  # exclude files from lower level already chunked directories in same tree
  #
  awk -F $'\t' '{printf "%s\n", $2}' $CHUNKED | grep -F "${dirname}" > $EXCLFILE
  if [ -s "${EXCLFILE}" ]
  then
    grep -F "${dirname}" $ALLFILES | grep -F -v -f $EXCLFILE > $TMPFILE
  else
    ## doing this results in 0 file chunks
    ##    fpart -s $FPARTBYTES -o $PARTITIONDIR/$chunk "$dirname"
    grep -F "${dirname}" $ALLFILES  > $TMPFILE
  fi

  # Let fpart do the hard work
  fpart -s $FPARTBYTES -o $PARTITIONDIR/$chunk -i $TMPFILE 
}

# ---------
usage() {
  echo "Usage: $0 [-s <chunk_size_kbytes>] [-o <part_dir> ] <directory_to_partition> " >&2
  exit 1
}

# --------------------------------------------------------------------
PARTITIONDIR="dparts"

while getopts "s:o:" option
do
  case $option in
    s)  CHUNKSIZE=$OPTARG ;;
    o)  PARTITIONDIR=$OPTARG ;;
    *)  usage ;;
  esac
done
shift $((OPTIND-1))

STARTDIR="$1"

if [ -z "$STARTDIR" ]
then
  echo "ERROR: You must define a starting directory to chunk"
  usage
fi

if [ ! -d "$STARTDIR" ]
then
  echo "ERROR: $STARTDIR does not exist or is not a directory"
  usage
fi

WORKDIR=`pwd`
if [ $(dirname $PARTITIONDIR) = '.' ]
then
  PARTITIONDIR=$WORKDIR/$PARTITIONDIR
fi 

INFOFILE="$PARTITIONDIR/dpart.readme"
DATFILE="$PARTITIONDIR/.dpart-data.txt" 
TMPFILE="$PARTITIONDIR/.dpart-data.tmp" 
EXCLFILE="$PARTITIONDIR/.dpart-data.exclude" 
CHUNKED="$PARTITIONDIR/.dpart-chunked.txt" 
ALLFILES="$PARTITIONDIR/.dpart-find.out"
DMDUOUT="$PARTITIONDIR/.dpart-du.out"


echo "Partitioning file names in $STARTDIR into chunks of size $CHUNKSIZE kbytes under directory $PARTITIONDIR"


if [ ! -d "$PARTITIONDIR" ] 
then
  mkdir "$PARTITIONDIR"
fi

#
# clean out data if different STARTDIR from previous run.
if [ ! -f $INFOFILE ] || ! grep -q -F "STARTDIR==${STARTDIR}==" $INFOFILE
then
  rm -f $ALLFILES
  rm -f $DMDUOUT
  echo "STARTDIR==${STARTDIR}==" > $INFOFILE
fi

# always clean out chunks
rm -f $PARTITIONDIR/chunk-*


#
# Generate input data to work out chunking
cd $STARTDIR

if [ ! -f $ALLFILES ]
then
  echo "Please wait. Finding all the files under $STARTDIR"
  find -H . ! -type d > $ALLFILES
fi

if [ ! -f $DMDUOUT ]
then
  echo "Please wait. Finding the sizes of directories under $STARTDIR"
  $DU . > $DMDUOUT
fi

echo "Working out the chunk lists - see $PARTITIONDIR for progress"

# find smallest dir chunk
#result=$(findleaves)
#echo $result

# 
# find lowest level "chunk"
#
awk -F \/ '{printf "%s\t%s\n", NF-1, $0}' $DMDUOUT | sort -nr  > $DATFILE

MAX_DEPTH=`awk -F $'\t' -v MAX=${CHUNKSIZE} '$2 > MAX {printf "%s\n", $1}' $DATFILE | head -1`


depth=$((MAX_DEPTH))
echo "maximum chunked directory depth = $depth"

#
# chunk size too small for dataset
if [ $depth -eq 0 ]
then
  #suggest=$(findleaves)
  #suggest=$((2 * $suggest))
  #echo "ERROR: select larger chunk size (I suggest $suggest ) or just use part"
  echo "ERROR: select larger chunk size or just use part as follows"
  chunk=`printf "chunk-%d-%d\n" 0 0`
  echo "  cd $STARTDIR;fpart -s $FPARTBYTES -o $PARTITIONDIR/$chunk ."
  exit 1
fi


cat /dev/null >  $CHUNKED

while [ $depth -ge 0 ]
do
  echo "checking directory level $depth"
  index=0
  awk  -F $'\t' -v MAX=${CHUNKSIZE} -v DEPTH=${depth} \
     '$1 == DEPTH && $2 > MAX {printf "%s/\n", $3}' $DATFILE | \
  while read -r line
  do
    partition $depth $index "$line"
    index=$(($index + 1))
  done 

  awk -F $'\t' -v MAX=${CHUNKSIZE} -v DEPTH=${depth} \
    '$1 == DEPTH && $2 > MAX {printf "%s\t%s/\n", $2, $3}' $DATFILE >> $CHUNKED

  depth=$(($depth - 1))
done


#
# Do some checks
#
echo
echo
TOTALFC=`cat $ALLFILES | wc -l`
CHUNKEDFC=`cat $PARTITIONDIR/chunk-* | wc -l`

echo "TOTAL FILE COUNT = $TOTALFC,  CHUNKED FILE COUNT = $CHUNKEDFC"
if [ $TOTALFC -ne $CHUNKEDFC ]
then
  echo "ERROR: There is a problem"
  exit 1
fi

echo "It all looks good!!"
