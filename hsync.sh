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

usage() {
  echo "Usage: $0 <start_dir> <destination> <file_list>" >&2
  echo "  <start_dir> and <file_list> need to have absolute paths" >&2
  exit 1
}

# determine files missing
# ------------------------
getmissingfiles() {
  missing_files="$1"

  echo ">determine what files are missing at '$DESTINATION'"

  if ! rsync -goDlt -ni -z --relative --recursive   \
     --files-from=$CHUNK \
     $RSYNC_OPTS \
     .  $DESTINATION | \
    grep "^>f" | sed -e "s/^>f[\+]* //"  > $missing_files
  then
    echo "ERROR: initial rsync failed" >&2
    exit 2
  fi

  COUNT=$(cat $missing_files | wc -l)
  if [ $COUNT -eq 0 ]
  then
    echo "  Files in $CHUNK are already synced to $DESTINATION"
    echo "    To retrieve space please do a '$CHUNK | dmput -r'"
    exit 0
  fi
  echo "  $COUNT files need to by synced"
}

# Get missing files off tape
# --------------------------
getfilesofftape() {
  mssing_files="$1"
  waiting_files="$2"

  echo ">getting OFL files from tape"
  UNMIGRATING=1
  while [ $UNMIGRATING -eq 1 ]
  do
    UNMIGRATING=0
    while read -r f
    do
      DMSTATE=$(dmattr -a state "$f")
      if [ "$DMSTATE" = "OFL" -o $DMSTATE = "UNM" ]  
      then
        UNMIGRATING=1
        echo "$f" >> $waiting_files
        if [ "$DMSTATE" = "OFL" ]
        then
          echo -n 'o'
          if ! dmget -q "$f"
          then
            echo "ERROR: problem getting '$f' from HSM" >&2
          fi
        else
          echo -n 'm'
        fi
      else
          echo -n '.'
      fi
    done < $missing_files
    echo

    if [ $UNMIGRATING -eq 1 ]
    then
      waitcount=$(cat $waiting_files | wc -l)
      echo "  Waiting $WAITFORHSM seconds for $waitcount files still on tape."
      echo "    See '$waiting_files' for a list of the files still Migrating"

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
     --files-from=$CHUNK \
     $RSYNC_OPTS \
     .  $DESTINATION 
  then
    echo "ERROR: syncing $CHUNK" >&2
    exit 2
  fi
  
  echo "  synced '$CHUNK'"
}


# verify files in chunk were copied
# ---------------------------------
verifyfilescopied() {
  echo "verify files were copied"
  rsync -goDlt -ni -z --relative --recursive   \
     --files-from=$CHUNK \
     $RSYNC_OPTS \
     .  $DESTINATION | \
    grep "^>f" | sed -e "s/^>f[\+]* //"  > $WAITINGFILES
  
  COUNT=`cat $WAITINGFILES | wc -l`
  if [ $COUNT -eq 0 ]
  then
    echo "  files were copied"
    echo "  now offlining files in chunk"
    cat $CHUNK | dmput -r
  fi
}


# ------------------------------------------------------------------
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
  echo "ERROR: no files in $CHUNK to sync" >&2
  exit 0
fi

# chunks should be relative to STARTDIR
cd $STARTDIR
TESTFILE=$(head -1 $CHUNK)
if [ ! -e "$STARTDIR/$TESTFILE" ]
then
  echo "ERROR: files in $CHUNK don't exist relative to $STARTDIR" >&2
  exit 2
fi


DIRNAME=`dirname $CHUNK`
BASENAME=`basename $CHUNK`


ERRFILE="$DIRNAME/.ER-$BASENAME"
OUTFILE="$DIRNAME/.OU-$BASENAME"

echo "Copying files in '$CHUNK'"
echo "  relative to '$STARTDIR' "
echo "  to '$DESTINATION'" 
echo
echo "You can monitor progress in"
echo "  '$DIRNAME/.OU-$BASENAME'"
echo "  '$DIRNAME/.ER-$BASENAME'"

exec 2> ${ERRFILE} > ${OUTFILE}


MISSINGFILES="$DIRNAME/.missing-$BASENAME"
cat /dev/null > $MISSINGFILES
getmissingfiles $MISSINGFILES


WAITINGFILES="$DIRNAME/.waiting-$BASENAME"
cat /dev/null > $WAITINGFILES

getfilesofftape $MISSINGFILES $WAITINGFILES

copyfiles

verifyfilescopied

