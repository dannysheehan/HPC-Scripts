#!/bin/bash
#
# This script is meant to run as a cron job on a HPC head node
#
BHOST=`uname -n`

DU_LIMIT_G=1000

VOLUME="$1"

if [ -n "$2" ] && [[ $2 =~ ^[0-9]+$ ]]
then
  DU_LIMIT_G="$2"
fi

# verify mode is the default.
VERIFY=1
if [ -n "$3 " -a "$3" = "--noverify" ]
then
  echo "sending tickets to users"
  VERIFY=0
fi



# -------------------------
processdu() {
  duinfo="$1"

  UNAME=$(echo "$duinfo" | cut -d\, -f1)
  UDIR=$(echo "$duinfo" | cut -d\, -f3)
  DUSIZE=$(echo "$duinfo" | cut -d\, -f4)
  TO_USER=$UNAME

  if [ $DUSIZE -gt $DU_LIMIT_G ]
  then
    # throttle user
    echo "set server max_run_res.ncpus += [u:$TO_USER=1]"
    qmgr -c "set server max_run_res.ncpus += [u:$TO_USER=1]"

    echo "$UNAME $UDIR $DUSIZE > $DU_LIMIT_G"

    if [ $VERIFY -eq 1 ]
    then
      return
    fi

    SUBJECT="ACTION REQUIRED: $UDIR Your disk usage on barrine ($DUSIZE GB) - your jobs will queue"
    MESSAGE=`cat << EOF
Hi %%NAME%%,\n
.\n
The Panasas storage is a high performance parallel storage technology\n
that is optimised for certain types of HPC workloads.\n
.We have **enforced quota usage** as follows:\n
.\n
....fs.....quota\n
../home....200GB \n
../work1...2000GB\n
../work2...>2000GB - access by special request only\n
.\n
Your $UDIR directory is currently over quota -> **${DUSIZE} GB** \n
.\n
Please archive or remove files immediately \n
**your jobs will queue** until you address the problem. \n
.\n
External users (eg CSIRO) should move their long term infreqently accessed data\n
to their own site.\n
UQ and QCIF users have the /HPC/home and /PROJ hierarchical storage \n
filesystems for that purpose.\n
.\n
Bioinformatics users can take advantage of /ebi/bscratch for short term storage.\n
.\n
As a reminder, /work1, /work2 and /home are not for long term storage of\n
files and are not backed up. They are for compute work only.\n
.\n
Reply to this ticket if you need help archiving your data so your jobs can run again.\n
.\n
Regards\n
RCC Admin\n
EOF
`
 else
   return
 fi

STATUS_CODE=`curl -s -o /dev/null -w "%{http_code}"  -X PUT -d @- \
 -H "Content-Type: application/json" \
 -H "X-Redmine-API-Key: $REDMINE_KEY" "$REDMINE_API" << EOF
{
   "username": "$TO_USER", 
   "subject": "$SUBJECT", 
   "message": "$MESSAGE",
   "type":"Filesystem quota exceeded",
   "issue": {
        "custom_field_values":{ 
                "8":"Hour or Less", 
                "7":"Negligible", 
                "19":0
        }
    }
}
EOF`

if [ $STATUS_CODE -ne 200 -a  $STATUS_CODE -ne 204 ]
then
  echo "ERROR: $TO_USER $STATUS_CODE" >&2
fi

}


# -------------------------
processerror() {
  error="$1"

  #/home/xxxxx:xxxxx:xx:MAXDIRFILESLIMIT:3147:/home/xxxxx/Planck_likelihoo


  UDIR=$(echo "$error" | cut -d\: -f1)
  ERROR_TYPE=$(echo "$error" | awk -F\: '{print $4}')

  #if [ ! -n "$TO_USER" ] 
  #then
  TO_USER=$(echo "$error" | cut -d\: -f2)
  #fi 

  if [ ! -n "$ERROR_TYPE" ]
  then
    return
  fi

  if [ "${ERROR_TYPE}" = "MAXDIRFILESLIMIT" ]
  then
    ERROR_DIR=$(echo "$error" | cut -d\: -f6)
    DIR_NUM=$(echo "$error" | cut -d\: -f5)

    echo "$TO_USER MAXDIRFILESLIMIT $DIR_NUM"

    if [ $VERIFY -eq 1 ]
    then
      return
    fi

    SUBJECT="ACTION REQUIRED: $UDIR contains directories with a large numbers of files ($DIR_NUM)"

    MESSAGE=`cat << EOF
Hi %%NAME%%,\n
.\n
You have directories under $UDIR that have thousands of files in them.\n
.\n
For Example:\n
.\n
.      $ERROR_DIR contains $DIR_NUM files\n
.\n
To see a complete list of directories containing large numbers of files\n
run the following on a barrine login node.\n
.\n
.      /usr/local/bin/lsdircount.sh $VOLUME\n
.\n
PANASAS filesystems work best for a small number of large files. \n
Performance is impacted when accessing directories containing large \n
numbers of small files.\n
You may have noticed this already when you try to access these directories.\n
.\n
Please compress, archive or remove these directories if they are\n
not actively being used for compute work.\n
.\n
/work1, /work2 and /home are not for long term storage of files\n
and are not backed up. They are for compute work only.\n
.\n
Reply to this ticket if you need help archiving or moving your data.\n
.\n
Regards\n
RCC Admin\n
\n
EOF
`
  elif [ "${ERROR_TYPE}" = "MAXFILESLIMIT" ]
  then
    echo "set server max_run_res.ncpus += [u:$TO_USER=1]"
    qmgr -c "set server max_run_res.ncpus += [u:$TO_USER=1]"

    FILE_NUM=$(echo "$error" | cut -d\: -f5)

    echo "$TO_USER MAXFILESLIMIT $FILE_NUM"

    if [ $VERIFY -eq 1 ]
    then
      return
    fi

    SUBJECT="ACTION REQUIRED: $UDIR is over quota for number of files ($FILE_NUM) - your jobs will queue"

    MESSAGE=`cat << EOF
Hi %%NAME%%,\n
.\n
We noticed your $UDIR directory contains $FILE_NUM files.\n
This is significantly over quota.\n
.\n
Please archive or remove files immediately \n
**your jobs will queue** until you address this problem \n
.\n
PANASAS filesystems work best for a small number of large files. \n
Performance is impacted when accessing directories containing large\n 
numbers of small files.\n
.\n
You may have noticed this already when trying to access directories.\n
.\n
Please archive or remove all files not actively being used for \n
compute work.\n
.\n
As a reminder, /work1, /work2 and /home are not for long term storage of\n
files and are not backed up. They are for compute work only.\n
.\n
Reply to this ticket if you need help archiving your data so your jobs can run again.\n
.\n
Regards\n
RCC Admin\n
EOF
`
 else
   return
 fi

STATUS_CODE=`curl -s -o /dev/null -w "%{http_code}"  -X PUT -d @- \
 -H "Content-Type: application/json" \
 -H "X-Redmine-API-Key: $REDMINE_KEY" "$REDMINE_API" << EOF
{
   "username": "$TO_USER", 
   "subject": "$SUBJECT", 
   "message": "$MESSAGE",
   "type":"Filesystem quota exceeded",
   "issue": {
        "custom_field_values":{ 
                "8":"Hour or Less", 
                "7":"Negligible", 
                "19":0
        }
    }
}
EOF`

if [ $STATUS_CODE -ne 200 -a  $STATUS_CODE -ne 204 ]
then
  echo "ERROR: $TO_USER $STATUS_CODE" >&2
fi


}

# ---------------------------------------------------------------------------

APANPATH="${VOLUME}/.apandu"

RDATE=`date -d date -d today +%Y-%m-%d`
ERR_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.ER"
CSV_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.csv"


if [ ! -e "$ERR_FILE" ]
then
  RDATE=`date -d date -d yesterday +%Y-%m-%d`
  ERR_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.ER"
  if [ ! -e "$ERR_FILE" ]
  then
    echo "ERROR: apan_du.sh has not been run the last day or two" >&2
    exit 1
  fi
  CSV_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.csv"
fi

if ! grep -q "^END:" "$ERR_FILE"
then
  echo "ERROR: apan_du.sh has not finished running or was terminated." >&2
  exit 1
fi

if [ ! -e "$CSV_FILE" ]
then
    echo "ERROR: no $CSV_FILE exists" >&2
    exit 1
fi


cat $CSV_FILE | while read d
do
  if [ ! -n "${d}" ]; then continue; fi
  if [ "${d}" != "${d/\#/}" ]; then continue; fi
  processdu "$d"
  exit 1
  sleep 5
done

cat $ERR_FILE | grep -v "^#" | while read e
do
  if [ ! -n "${e}" ]; then continue; fi

  if [ "${e}" != "${e/START/}" ]; then continue; fi
  if [ "${e}" != "${e/END:/}" ]; then continue; fi
  if [ "${e}" != "${e/pan_du:/}" ]; then continue; fi

  processerror "$e"
  exit 1
  sleep 5
done

