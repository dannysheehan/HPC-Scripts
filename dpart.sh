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
#  Usage: $0 [-s <chunk_size_kbytes>] [-f <chunk_file_count] [-o <part_dir> ] <directory_to_partition> " >&2
#
# -------------------------------------------------------------------------------
export PATH=$PATH:/usr/local/bin:/sw/fpart/0.9.2/bin/

DU="du"
DMDU="dmdu"
SUGGESTSIZE=0


# 20 GiByte default chunk size
CHUNKSIZE=$((15*1024*1024))

FPARTBYTES=$((2*$CHUNKSIZE*1024))
FPARTFILES=400


# ---------
findleaves() {
  maxdirsize=0
  maxdir=""
  while IFS= read -r -d '' line
  do
    dirname=`echo "$line" | awk  -F $'\t' 'BEGIN { RS = "\0" } {print $3}'`
    if ! grep -FZzaq "$dirname/" $DATFILE  > /dev/null
    then
      chunksize=`echo "$line" | awk  -F $'\t' 'BEGIN { RS = "\0" } {print $2}'`
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
  awk -F $'\t' 'BEGIN { RS = "\0" } {printf "%s\0", $2}' $CHUNKED | \
    grep -Fza "${dirname}" | tr '\0' '\n' > $EXCLFILE
  if [ -s "${EXCLFILE}" ]
  then
    grep -Fza "${dirname}" $ALLFILES | \
       grep -Fzav -f $EXCLFILE | tr '\0' '\n' > $TMPFILE
  else
    grep -Fza "${dirname}" $ALLFILES  | \
       tr '\0' '\n'  > $TMPFILE
  fi

  # Let fpart do the hard work
  # it dosn't have option to handle null terminated input files
  fpart -s $FPARTBYTES -o $PARTITIONDIR/$chunk -f $FPARTFILES -i "$TMPFILE" 
}

# ---------
usage() {
  echo "Usage: $0 [-c] [-s <chunk_size_kbytes>] [-e <exlude_paths] [-f <chunk_file_count] [-o <part_dir> ] <directory_to_partition> " >&2
  exit 1
}

# --------------------------------------------------------------------
PARTITIONDIR="dparts"
EXCLPATHS=""

while getopts "cs:o:f:e:" option
do
  case $option in
    c)  SUGGESTSIZE=1 ;;
    s)  CHUNKSIZE=$OPTARG ;;
    o)  PARTITIONDIR=$OPTARG ;;
    f)  FPARTFILES=$OPTARG ;;
    e)  EXCLPATHS=$OPTARG ;;
    *)  usage ;;
  esac
done
shift $((OPTIND-1))

STARTDIR="$1"

if [ -n "$EXCLPATHS" ] && \
   [ ! -f "$EXCLPATHS" -o -z "$EXCLPATHS" -o ${EXCLPATHS:0:1} != '/' ]
then
  echo "ERROR: <exclude_paths> must exist and  be an absolute path" >&2
  usage
fi

if ! which fpart 2> /dev/null > /dev/null
then
  echo "ERROR: 'fpart' needs to be installed and in your PATH" >&2
  usage
fi    

if [ -z "$STARTDIR" ]
then
  echo "ERROR: You must define a starting directory to chunk" >&2
  usage
fi

if [ ! -d "$STARTDIR" ]
then
  echo "ERROR: $STARTDIR does not exist or is not a directory" >&2
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
DUOUT="$PARTITIONDIR/.dpart-du.out"

EXALLFILES="$PARTITIONDIR/.dpart-find.excluded"
EXDUOUT="$PARTITIONDIR/.dpart-du.excluded"


echo "Partitioning file names in $STARTDIR into chunks"
echo "  under:      $PARTITIONDIR"
echo "  maxsize:  $CHUNKSIZE kbytes (-s option)"
echo "  maxfiles: $FPARTFILES (-f option)"


if [ ! -d "$PARTITIONDIR" ] 
then
  mkdir "$PARTITIONDIR"
else
  # always clean out chunks. There could be a lot so do one at a time
  cd $PARTITIONDIR
  find . -name "chunk-*" | xargs -l1 rm -f
fi

#
# clean out data if different STARTDIR from previous run.
if [ ! -f $INFOFILE ] || ! grep -q -F "STARTDIR==${STARTDIR}==" $INFOFILE
then
  rm -f $ALLFILES
  rm -f $DUOUT
  echo "STARTDIR==${STARTDIR}==" > $INFOFILE
fi


#
# Generate input data to work out chunking
cd $STARTDIR

if [ ! -f "$ALLFILES" -o ! -s "$ALLFILES" ]
then
  echo "Please wait. Finding all the files under $STARTDIR"
  find -H . ! -type d -print0 > $ALLFILES
fi

DMSTATE=""
# check for HSM filesystem
if which $DMDU 2> /dev/null > /dev/null
then
  DMSTATE=$(dmattr -a state . 2> /dev/null)
  if [ $? -eq 0 -a -n "$DMSTATE" ]
  then
    DU=$DMDU
  fi

fi
# TODO check for PANASAS filesytem and use pan_du
echo "  using:    $DU"

if [ ! -f "$DUOUT" -o ! -s "$DUOUT" ]
then
  echo "Please wait. Finding the sizes of directories under $STARTDIR"

  # dmdu has no null terminated file output option.
  if [ -n "$DMSTATE" ]
  then
    $DU . | tr '\n' '\0' > $DUOUT
  else
    $DU -0 . > $DUOUT
  fi

fi

if [ -n "$EXCLPATHS" ]
then
   echo "  excluding: $EXCLPATHS (-e option)"
   grep -Fzav -f $EXCLPATHS $ALLFILES > $EXALLFILES
   ALLFILES=$EXALLFILES

   # du does not put trailing / on directories so remove just for this test.
   sed -e "s/\/$//" $EXCLPATHS > $TMPFILE
   grep -Fzav -f $TMPFILE $DUOUT > $EXDUOUT
   DUOUT=$EXDUOUT
fi


if [ $SUGGESTSIZE -eq 1 ]
then
  # find smallest dir chunk
  result=$(findleaves)
  result=$(($result - 1))
  echo "Recommended chunk size is $result"
  exit 0
fi

echo "Working out the chunk lists - see $PARTITIONDIR for progress ($DU)"


# 
# find lowest level "chunk"
#
awk -F \/ 'BEGIN { RS = "\0" } {printf "%s\t%s\0", NF-1, $0}' $DUOUT | \
    sort -znr  > $DATFILE

MAX_DEPTH=`awk -F $'\t' -v MAX=${CHUNKSIZE} 'BEGIN { RS ="\0" } $2 > MAX {printf "%s\n", $1}' $DATFILE | head -1`


depth=$((MAX_DEPTH))
echo "maximum chunked directory depth = $depth"

#
# chunk size too small for dataset
if [ $depth -eq 0 ]
then
    echo "ERROR: select smaller chunk size (use -c option) or just use part as follows"
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
   'BEGIN { RS = "\0" } $1 == DEPTH && $2 > MAX {printf "%s/\0", $3}' \
   $DATFILE | \
  while IFS= read -r -d '' line
  do
    partition $depth $index "$line"
    index=$(($index + 1))
  done 

  awk -F $'\t' -v MAX=${CHUNKSIZE} -v DEPTH=${depth} \
   'BEGIN { RS = "\0" } $1 == DEPTH && $2 > MAX {printf "%s\t%s/\0", $2, $3}' \
   $DATFILE >> $CHUNKED

  depth=$(($depth - 1))
done


#
# Do some checks
#
echo
echo
TOTALFC=`cat $ALLFILES | tr '\0' '\n' | wc -l`
CHUNKEDFC=`cat $PARTITIONDIR/chunk-* | wc -l`

echo "TOTAL FILE COUNT = $TOTALFC,  CHUNKED FILE COUNT = $CHUNKEDFC"
if [ $TOTALFC -ne $CHUNKEDFC ]
then
  echo "ERROR: There is a problem"
  exit 1
fi

echo "It all looks good!!"
