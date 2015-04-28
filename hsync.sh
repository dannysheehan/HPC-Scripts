#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :hsync.sh
#description    :a wrapper for rsync that uses migrates fpart chunks from HSM
#author         :Danny W Sheehan
#date           :March 2015
#
#  Usage: $0 <start_dir> <destination> <file_list>
#
#---------------------------------------------------------------------------

WAITFORHSM=60
CONTIMEOUT=7
IGNOREHSM=0
VERIFY=0

DELIM_OPT=""
CONTO_OPT="--contimeout=$CONTIMEOUT"

# determine files missing
# ------------------------
getmissingfiles() {
  the_chunk="$1"
  missing_files="$2"

  echo ">determine what files are missing at '$DESTINATION'"
  if ! eval "rsync -goDlt -ni -z --relative $RSYNC_OPTS \
     $DELIM_OPT \
     $CONTO_OPT \
     --files-from=$the_chunk \
     .  $DESTINATION" >  $TMPFILE
  then
    echo "ERROR: getmissingfiles() initial rsync failed" >&2
    exit 2
  fi

  grep "^[<>]f" $TMPFILE | sed -e "s/^[<>]f[\+\.cstpogax]* //" > $missing_files
  rm -f $TMPFILE

  COUNT=$(cat $missing_files | wc -l)
  if [ $COUNT -eq 0 ]
  then
    echo "  Files in $the_chunk are already synced to $DESTINATION"
    if [ $IGNOREHSM -ne 1 ]
    then
      echo "    To retrieve space please run '$the_chunk | dmput -r'"
    fi
    exit 0

  elif [ -n "$DELIM_OPT" -a $VERIFY -eq 0 ]
  then
    # dmattr and dmget don't support -0 option in older versions.
    # so convert back to newline terminated.
    # we also need to dmget on the complete chunk not just the missing
    # files as the output from rsync diff changes the non ascii characters
    # for readability which will break the dmgets.
    tr '\0' '\n' < $the_chunk > $missing_files
  fi

  echo "  $COUNT files need to by synced"
}

# Get missing files off tape
# --------------------------
getfilesofftape() {
  missing_files="$1"
  waiting_files="$2"

  tries=0

  SLEEPSECS=$[ ( $RANDOM % $WAITFORHSM ) + 1 ]
  echo ">getting $waitcount OFL/UNM files from tape"
  echo "    sleeping $SLEEPSECS seconds so as not to overload HSM"
  sleep $SLEEPSECS

  waitcount=$(cat $missing_files | wc -l)
  while [ $waitcount -gt 0 ]
  do
    tries=$((tries + 1))

    if ! dmattr -d$'\t' -a state,path < $missing_files > $TMPFILE
    then
      echo "ERROR: dmattr files from tape for $missing_files" >&2
      exit 3
    fi

    awk -F$'\t' \
     '$1 == "OFL" || $1 == "UNM" {printf "%s\n", $2}' $TMPFILE > $waiting_files

    if ! dmget -q < $waiting_files
    then
      echo "ERROR: dmget files from tape for $waiting_files" >&2
      exit 3
    fi

    waitcount=$(cat $waiting_files | wc -l)

    if [ $waitcount -gt 0 ]
    then
      # exponential backoff
      SLEEPSECS=$[ (2 * $SLEEPSECS) ]
      echo "  Try $tries: Waiting $SLEEPSECS seconds for $waitcount files still on tape."
      echo "    See '$missing_files' for a list of the files still migrating"

      cp $waiting_files $missing_files
      cat /dev/null > $waiting_files

      sleep $SLEEPSECS
    fi
  done

  echo "  files successfully unmigrated from tape"
}

# copy files in chunk to destination
# ----------------------------------
copyfiles() {
  the_chunk="$1"
  echo "syncing '$the_chunk'"
  if ! eval "rsync -goDlt -z --relative  \
     $RSYNC_OPTS \
     $DELIM_OPT \
     $CONTO_OPT \
     --files-from=$the_chunk \
     .  $DESTINATION" 
  then
    echo "ERROR: syncing $the_chunk" >&2
    exit 3
  fi
  
  echo "  synced '$the_chunk'"
}


# verify files in chunk were copied
# ---------------------------------
verifyfilescopied() {
  the_chunk="$1"
  missing_files="$2"

  echo "verify files were copied"
  if ! eval "rsync -goDlt -ni -z --relative \
     $RSYNC_OPTS \
     $DELIM_OPT \
     $CONTO_OPT \
     --files-from=$the_chunk \
     .  $DESTINATION" > $TMPFILE
  then
    echo "ERROR: initial rsync failed" >&2
    exit 4
  fi

  grep "^[<>]f" $TMPFILE | sed -e "s/^[<>]f[\+\.cstpogax]* //" > $missing_files
  rm -f $TMPFILE

  
  COUNT=`cat $missing_files | wc -l`
  if [ $COUNT -eq 0 ]
  then
    echo "  files were copied"
    if [ $IGNOREHSM -ne 1 ]
    then
      echo "  now offlining files in chunk"
      cat $the_chunk | dmput -r
    fi
  else
    echo "ERROR: There are still $COUNT missing files. See '$missing_files'" >&2
    exit 5
  fi
}

usage() {
  echo "Usage: $0 [-v] [-i] <start_dir> <destination> <file_list> [rsync options]" >&2
  echo "  <start_dir> and <file_list> need to have absolute paths" >&2
  exit 1
}



# ------------------------------------------------------------------
while getopts "iv" option
do
  case $option in
    v)  VERIFY=1 ;;
    i)  IGNOREHSM=1 ;;
    *)  usage ;;
  esac
done
shift $((OPTIND-1))

STARTDIR="$1"
shift
DESTINATION="$1"
shift
CHUNK="$1"
shift
RSYNC_OPTS=$@



if [ -z "$STARTDIR" ] || [ ! -d "$STARTDIR" ] || [ ${STARTDIR:0:1} != '/' ]
then
   echo "ERROR: You must define an absolute path for <start_dir> and '$STARTDIR' must exist" >&2
   usage
fi

if [ -z "$DESTINATION" ]
then
   echo "ERROR: you must define an rsync <destination>"
   usage
fi

if [ -z "$CHUNK" ] || [ ! -f "$CHUNK" ] || [ ${CHUNK:0:1} != '/' ]
then  
   echo "ERROR: <file_list> required and must be an absolute path" >&2
   usage
fi

# chunk should have some files in it
if [ $(cat $CHUNK | wc -l) -eq 0 ]
then
  echo "ADVISORY: no files in $CHUNK to sync" >&2
  exit 0
fi



# chunks should be relative to STARTDIR
cd $STARTDIR
TESTFILE=$(head -1 $CHUNK)
if [ ! -f "$TESTFILE" -a ! -h "$TESTFILE" ]
then
  echo "ERROR: files in $CHUNK don't exist relative to $STARTDIR" >&2
  echo "ERROR: $TESTFILE" >&2
  exit 6
fi

# Don't use these options if NOT connecting to an rsync daemon
if [ "${DESTINATION}" = "${DESTINATION/::/}" ]
then
  CONTO_OPT=""
fi


DIRNAME=`dirname $CHUNK`
BASENAME=`basename $CHUNK`


TMPFILE="$DIRNAME/.TMP-$BASENAME"
ERRFILE="$DIRNAME/.ER-$BASENAME"
OUTFILE="$DIRNAME/.OU-$BASENAME"
NULLFILE="$DIRNAME/.0-$BASENAME"

echo "Copying files in '$CHUNK'"
echo "  relative to '$STARTDIR' "
echo "  to '$DESTINATION'" 
if [ -n "${RSYNC_OPTS}" ]; then echo "  options '$RSYNC_OPTS'"; fi
if [ -n "${RSYNC_PASSWORD}" ]; then echo "  RSYNC_PASSWORD set"; fi

echo
echo "You can monitor progress in"
echo "  '$DIRNAME/.OU-$BASENAME'"
echo "  '$DIRNAME/.ER-$BASENAME'"

exec 2> ${ERRFILE} > ${OUTFILE}

# check for non-ascii and automatically convert to binary sync.
if grep -q -P  "[\x00-\x09\x0b-\x1f\x7f-\xff]"  $CHUNK
then
 DELIM_OPT='-0'
 tr '\n' '\0' < $CHUNK > $NULLFILE
 CHUNK=$NULLFILE
 echo "contains non-ascii file names"
fi 


MISSINGFILES="$DIRNAME/.missing-$BASENAME"
cat /dev/null > $MISSINGFILES
getmissingfiles $CHUNK $MISSINGFILES

if [ $VERIFY -eq 1 ]
then
  COUNT=$(cat $MISSINGFILES | wc -l)
  if [ $COUNT -ne 0 ]
  then
    echo "VERIFY: see $MISSINGFILES for files that are missing" 
  fi
  exit 0
fi


WAITINGFILES="$DIRNAME/.waiting-$BASENAME"
cat /dev/null > $WAITINGFILES

if [ $IGNOREHSM -ne 1 ]
then
  getfilesofftape $MISSINGFILES $WAITINGFILES
fi

copyfiles $CHUNK

cat /dev/null > $MISSINGFILES
verifyfilescopied $CHUNK $MISSINGFILES

