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

WAITFORHSM=300
CONTIMEOUT=7
IGNOREHSM=0

DELIM_OPT=""
CONTO_OPT="--contimeout=$CONTIMEOUT"

# determine files missing
# ------------------------
getmissingfiles() {
  missing_files="$1"

  echo ">determine what files are missing at '$DESTINATION'"

  if ! rsync -goDlt -ni -z --relative --recursive   \
     $RSYNC_OPTS \
     $DELIM_OPT \
     $CONTO_OPT \
     --files-from=$CHUNK \
     .  $DESTINATION >  $TMPFILE
  then
    echo "ERROR: initial rsync failed" >&2
    exit 2
  fi

  grep "^[<>]f" $TMPFILE | sed -e "s/^[<>]f[\+]* //"  > $missing_files
  rm -f $TMPFILE

  COUNT=$(cat $missing_files | wc -l)
  if [ $COUNT -eq 0 ]
  then
    echo "  Files in $CHUNK are already synced to $DESTINATION"
    if [ $IGNOREHSM -ne 1 ]
    then
      echo "    To retrieve space please run '$CHUNK | dmput -r'"
    fi
    exit 0
  fi
  echo "  $COUNT files need to by synced"
}

# Get missing files off tape
# --------------------------
getfilesofftape() {
  mssing_files="$1"
  waiting_files="$2"

  waitcount=0

  echo ">getting OFL files from tape"
  UNMIGRATING=1
  while [ $UNMIGRATING -eq 1 ]
  do
    UNMIGRATING=0
    waitcount=0
    while read -r f
    do
      DMSTATE=$(dmattr -a state "$f")
      if [ $? -ne 0 ]
      then
        echo "ERROR: problem getting '$f' state from HSM " >&2
        # don't exit try again next time
        echo -n 'e'
      elif [ "$DMSTATE" = "OFL" -o "$DMSTATE" = "UNM" ]  
      then
        UNMIGRATING=1

        echo "$f" >> $waiting_files

        if [ "$DMSTATE" = "OFL" ]
        then
          if ! dmget -q "$f"
          then
            echo "ERROR: problem getting '$f' from HSM" >&2
            # don't exit try again next time
            echo -n 'e'
          else
            echo -n 'o'
          fi
        else
          echo -n 'm'
        fi
      else
          echo -n '.'
      fi

      waitcount=$((waitcount + 1))
      if [ $(($waitcount % 80)) -eq 0 ]; then echo; fi
    done < $missing_files

    echo
    if [ $UNMIGRATING -eq 1 ]
    then
      echo "  Waiting $WAITFORHSM seconds for files still on tape."
      echo "    See '$missing_files' for a list of the files still migrating"

      cp $waiting_files $missing_files
      cat /dev/null > $waiting_files
      sleep $WAITFORHSM
    fi
  done

  echo "  files successfully unmigrated from tape"
}

# copy files in chunk to destination
# ----------------------------------
copyfiles() {
  echo "syncing '$CHUNK'"
  if ! rsync -goDlt -z --relative --recursive   \
     $RSYNC_OPTS \
     $DELIM_OPT \
     $CONTO_OPT \
     --files-from=$CHUNK \
     .  $DESTINATION 
  then
    echo "ERROR: syncing $CHUNK" >&2
    exit 3
  fi
  
  echo "  synced '$CHUNK'"
}


# verify files in chunk were copied
# ---------------------------------
verifyfilescopied() {
  mssing_files="$1"

  echo "verify files were copied"
  if ! rsync -goDlt -ni -z --relative --recursive   \
     $RSYNC_OPTS \
     $DELIM_OPT \
     $CONTO_OPT \
     --files-from=$CHUNK \
     .  $DESTINATION > $TMPFILE
  then
    echo "ERROR: initial rsync failed" >&2
    exit 4
  fi

  grep "^[<>]f" $TMPFILE | sed -e "s/^[<>]f[\+]* //"  > $missing_files
  rm -f $TMPFILE

  
  COUNT=`cat $missing_files | wc -l`
  if [ $COUNT -eq 0 ]
  then
    echo "  files were copied"
    if [ $IGNOREHSM -ne 1 ]
    then
      echo "  now offlining files in chunk"
      cat $CHUNK | dmput -r
    fi
  else
    echo "ERROR: There are still $COUNT missing files. See '$missing_files'" >&2
    exit 5
  fi
}

usage() {
  echo "Usage: $0 [-0] [-i] <start_dir> <destination> <file_list>" >&2
  echo "  <start_dir> and <file_list> need to have absolute paths" >&2
  exit 1
}



# ------------------------------------------------------------------
while getopts "i" option
do
  case $option in
    i)  IGNOREHSM=1 ;;
    *)  usage ;;
  esac
done
shift $((OPTIND-1))

STARTDIR="$1"
DESTINATION="$2"
CHUNK="$3"

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
getmissingfiles $MISSINGFILES


WAITINGFILES="$DIRNAME/.waiting-$BASENAME"
cat /dev/null > $WAITINGFILES

if [ $IGNOREHSM -ne 1 ]
then
  getfilesofftape $MISSINGFILES $WAITINGFILES
fi

copyfiles

verifyfilescopied $MISSINGFILES

