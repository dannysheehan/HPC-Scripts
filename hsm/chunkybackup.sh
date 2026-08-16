#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title       :chunkybackup.sh
#description :tar up small files into specified sized chunks to backup to HSM storage.
#author      :Danny W Sheehan
#date        :July 2014
#website     :www.setuptips.com
# ----------------------------------------------------------------------
# chunkybackup.sh <directory> <backup-file> <chunksize>
#
# This script backups up the specified <directory> across N number of tar files
# of size <chunksize>. The tar files are named <backup-file>.x.tgz where 
# x is from 1..N, and are created in the users <HSM>/<username> directory.
#
# <directory>   = directory to backup
# <backup-file> = name to use on backup files e.g. <backup-file>.1.tgz
# <chunk-size>  = the maximim chunk size for each tar file in GB
#
# NOTE: Must be run as the user whose data is being backed up, not as root.
# su - <user>
# chunkybackup.sh /home/<user> home_backup 20
# e.g. #userx> chunkybackup.sh /home/userx work1_backup 20
#
# This script is also intended to overcome the quota limits on /HSM storage
# in cases where users want to backup /home or other work data areas in
# excess of their quota limits.
#
# The script is fairly robust. If interrupted and restarted it will continue 
# the backup from where it left off (to the nearest chunk) by first verifying 
# what files have already been backed up. 
# ASSUMPTION: No files were added since the backup was interrupted.
#
# ENV variables used
# $USER -- user running script
# $HOST -- node that this script is running on.
# $TMPDIR -- if run from batch job
#
# <backup-file>.x.tgz.txt files are also created under <HSM>/<username> so 
# users can quickly determine which tar file a paticular file or directory is 
# located in.
#
# Script uses $SCRATCH_DIR as a temporary staging area, and uses dmput to 
# migrate each chunk to tape. When quota is reached the script sleeps until 
# the tape drives catch up and quota usages goes down. 
# This overcomes the HSM quota limit.
#
# To avoid corrupt backups, checks are made of the available space in 
# $SCRATCH_DIR before tar files are created,  checks of the users quota in 
# /HSM/<username> before the tar files are copied in, and the copied chunks 
# are verified before chunks are written to tape.
#
# http://tiamat.name/blogposts/fast-appending-files-to-tar-archive-is-impossible/
# ----------------------------------------------------------------------

trap cleanup 1 2 3 6

ADIR=$1
BNAME=$2
TLIMITG=$3
# Suggested Default: Use 10 GB 
# TLIMITG=10000


# Users HSM directory. Change accoudingly for your site.
HSMDIR="/HPC/home/$USER"

# The script uses TMPDIR if it exists as the scratch area, 
# otherwise  it will use the following directory. Change according to your site.
SCRATCH_DIR="/var/tmp/$USER"
# SCRATCH_DIR="/scratch/$USER"


USAGE="Usage: `basename $0` <directory> <backup-name> <chunksize GB>"

if [ $# -ne 3 ]
then
  echo $USAGE
  echo
  echo "
 This script backups up the specified <directory> across N number of tar files
 of size <chunksize>. The tar files are named <backup-file>.x.tgz where
 x is from 1..N, and are created in the users $HSMDIR directory.

 <directory>   = directory to backup
 <backup-file> = name to use on backup files e.g. <backup-file>.1.tgz
 <chunk-size>  = the maximim chunk size for each tar file in GB

 e.g. chunkybackup.sh /work1/uquser work1_backup 20
 Creates $HSMDIR/work1_backup.1.tgz  etc.

 <backup-file>.x.tgz.txt files are also created under $HSMDIR so users can 
 quickly determine which tar file a paticular file or directory is located in.

 The script is fairly robust. If interrupted and restarted it will continue 
 the backup from where it left off (to the nearest chunk) by first verifying 
 what files have already been backed up. ASUMPTION: No files were added since 
 the backup was interrupted.
"


  exit 1
fi

# Chunk size must be at least 10 GB. 
# Tune according to your site.
if [ $TLIMITG -lt 10 -o $TLIMITG -gt 90 ]
then
  echo "chunk size must be >= 10GB but <= 90G" >&2
  echo $USAGE >&2
  exit 1
fi

if [ ! -d $ADIR ]
then
  echo "<directory> must be a directory." >&2
  echo $USAGE >&2
  exit 1
fi

# You can't run script as root.
if [ "$(id -u)" = 0 ]
then
    echo "ERROR: $0 You must run script as a specific user not root." >&2
    exit 2
fi

if [ -n "$TMPDIR" -a -d "$TMPDIR" ]
then
  SCRATCH_DIR=$TMPDIR
else
  mkdir -p $SCRATCH_DIR
fi

# List of files to backup.
TARLIST="$SCRATCH_DIR/tarlist.txt"

# List of files in current tar chunk
CHUNKTARLIST="$SCRATCH_DIR/chunktarlist.txt"

# Base archive file path and name.
BFILE="$SCRATCH_DIR/$BNAME"


# Time in minutes to wait for quota usage to go down.
QUOTA_WAIT=10

# Keep a 10g buffer of spare quota in HSM.
BUFFERK=$((10*1024))

# convert chunk size to MB KB AND bytes.
TLIMITM=$(($TLIMITG*1024))
TLIMITK=$(($TLIMITM*1024))
TLIMITB=$(($TLIMITK*1024))

# -------------------------------------------------------------------
cleanup()
{
  echo "Caught Signal ... cleaning up."
  rm -rf ${SCRATCH_DIR}/${BNAME}.*
  rm -f $CHUNKTARLIST
  rm -f $TARLIST
  echo "Done cleanup ... quitting."
  exit 1
}


# -------------------------------------------------------------------
# Put the chunk to tape only if there is enough quota - otherwise sleep
# and wait for quota to go down as data is offlined to tape.
dmput_chunk()
{
  if [ ! -d $HSMDIR ]
  then
    echo "ERROR: $0 $HSMDIR does not exist." >&2
    exit 4
    
  else

    # Check if user has enough quota for a chunk and wait a bit if not.
    HSMQUOTA=`quota -v -f $HSMDIR | tail -1 |awk '{print ($2-$1)}'`
    while [ -n "$HSMQUOTA" ] && [ $HSMQUOTA -lt $(( $TLIMITK + $BUFFERK )) ]
    do

      echo "sleeping $QUOTA_WAIT minutes waiting for quota to increase to $TLIMITK kB from $HSMQUOTA kb"
      sleep $(( 60 * $QUOTA_WAIT ))

      HSMQUOTA=`quota -v -f $HSMDIR | tail -1 |awk '{print ($2-$1)}'`
    done
    echo "You have enough quota $HSMQUOTA kB > $TLIMITK kB under HSM"

    # Since there is NOW enough HSM quota we can copy our archive to HSM.
    echo "copying $AFILE to $HSMDIR"
    cp $AFILE $HSMDIR

    AFILENAME=`basename $AFILE`

    echo "checking if file is corrupt before putting to tape"
    tar -tzPf $HSMDIR/$AFILENAME > $HSMDIR/$AFILENAME.txt
    if [ $? -ne 0 ]
    then
      echo "ERROR: $0 corrupt tar file $HSMDIR/$AFILENAME" >&2
      exit 5
    else
      echo "    Good!! $HSMDIR/$AFILENAME is not corrupt."
      echo "Contents listing saved to $HSMDIR/$AFILENAME.txt for your future reference."
    fi
      echo "dmput -r $HSMDIR/$AFILENAME to tape"
      dmput -r $HSMDIR/$AFILENAME

      # cleanup $SCRATCH_DIR.
      rm $AFILE
  fi
}


# M A I N
# #############


# Find biggest file to be backed up and check it is less than the 
# user specified chunk size.
echo "Finding your largest file size - this may take a little time."

LARGESTFILE=`find $ADIR/ -type f -print0 | xargs -0 ls -l | sort -r -n -k 5,5 |  head -1 | awk '{print $5}'`

NEWCHUNKG=$(( $LARGESTFILE/1024/1024/1024 ))

echo "Your largest file size is $LARGESTFILE bytes"

if [ $LARGESTFILE -gt $TLIMITB ] 
then
    echo "ERROR: $0 Increase your <chunksize> to at least $NEWCHUNKG GB" >&2
    exit 2
fi
echo "Your selected chunk size of $TLIMITG GB is adequate."


CHUNK=1;
AFILE="$BFILE.$CHUNK.tgz"
if [ -f $AFILE ]
then
 echo "ERROR: $0 Please move/remove $AFILE before running this script." >&2
 exit 7
fi

# Start the first list of tar files.
touch $CHUNKTARLIST

# tar file size
ASIZE=0
find "$ADIR/" > $TARLIST
cat $TARLIST | while read f
do

  # unlikely but maybe someone deleted a file underneath us.
  if [ ! -e "$f" ];then continue; fi

  # skip if starting directory is symbolic link.
  if [ "$f" = "${ADIR}/" -a -h ${f%/} ]
  then
    echo "root dir is symbolic link skip it"
    continue
  fi

  # if the verify backup contents file is there then just check if files 
  # are alreay archived.
  AFILENAME=`basename $AFILE`
  if [ -e  "$HSMDIR/${AFILENAME}.txt" ]
  then

    if [ "$ADIR/" = "$f" ]
    then 
      echo;echo "Checking $HSMDIR/${AFILENAME}";echo
      continue
    fi

    # if not symblolic link to a directory then add trailing /.
    if [ ! -h "$f" -a  -d "$f" ];then f="$f/"; fi


    # See if file was previously archived and continue verification if it was.
    grep -q -x "$f" $HSMDIR/${AFILENAME}.txt
    if [ $? -eq 0 ]
    then
      echo -n "."
      continue
    else
      # Not found? Then see if is in the second archive. If it exists.
      CHUNK=`expr $CHUNK + 1`
      AFILE="$BFILE.$CHUNK.tgz"
      AFILENAME=`basename $AFILE`
      if [ -e "$HSMDIR/${AFILENAME}.txt" ]
      then
        echo;echo "Checking $HSMDIR/${AFILENAME}";echo
        grep -q -x "$f" $HSMDIR/${AFILENAME}.txt
        if [ $? -eq 0 ]
        then
          echo -n "."
          continue
        else
          echo "ERROR: $0 $f is missing from $AFILE - you need to redo your backup." >&2
          exit 6
        fi
      else
        # verification file does not exist so continue backup from where
        # last backup left off.
        echo;echo;echo "Continuing backup from where it was interrupted."
      fi
    fi
  fi

  # If the tar file exists then last backup must have failed.
  # i.e. verify file is missing.
  if [ -e "$HSMDIR/$AFILENAME" ]
  then
    echo "ERROR: $0 You need to remove $HSMDIR/$AFILENAME and restart your backup." >&2
    exit 6

  else 
    # check if there is sufficient staging space for a new chunk.
    SCRATCHAVAIL=`df -k  $SCRATCH_DIR | awk '{print $4}' | tail -1`
    if [ $SCRATCHAVAIL -lt $TLIMITK ]
    then
      echo "ERROR: $0 Not enough space in $SCRATCH_DIR on $HOST. Try another node" >&2
      exit 7
    fi

    # Build list of files that fit neatly into a chunk.
    echo;echo "creating archive in stage area -- $AFILE"
    touch ${AFILE}

    # http://en.wikipedia.org/wiki/Tar_(computing)
    # Each file object includes any file data, 
    # and is preceded by a 512-byte header record
    FSIZE=`stat --printf="%s" "$f"`
    ASIZE=`expr ${ASIZE} + ${FSIZE} + 512`
    while [ $ASIZE -lt $TLIMITB -a -n "$f"  ]
    do
      echo "$f"

      if read f
      then 
        FSIZE=`stat --printf="%s" "$f"`
        ASIZE=`expr ${ASIZE} + ${FSIZE} + 512`
      else
        # the end of the backup
        f=""
      fi
    done >> ${CHUNKTARLIST}

    # build tar file in $SCRATCH_DIR from list of files that fit neatly into
    # a chunk.
    tar --no-recursion -czPf ${AFILE} -T $CHUNKTARLIST
    rm -f $CHUNKTARLIST

    # now dump chunk to tape.
    dmput_chunk
 
    # Now for the file that didn't fit in the chunk.
    if [ -n "$f" ] 
    then
      # add to start of new tar file list 
      FSIZE=`stat --printf="%s" "$f"`
      ASIZE=`expr ${FSIZE} + 512`
      echo "$f" > $CHUNKTARLIST 

      # ...and start a new chunk.
      CHUNK=`expr $CHUNK + 1`
      AFILE="$BFILE.$CHUNK.tgz"
      AFILENAME=`basename $AFILE`
    fi
  fi

done

echo;echo "verification/backup complete"
rm -f $TARLIST
