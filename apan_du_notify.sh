#!/bin/bash
#
# This script is meant to run as a cron job on a HPC head node
#
BHOST=`uname -n`

VOLUME="$1"

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
    continue
  fi

  if [ "${ERROR_TYPE}" = "MAXDIRFILESLIMIT" ]
  then
    ERROR_DIR=$(echo "$error" | cut -d\: -f6)
    DIR_NUM=$(echo "$error" | cut -d\: -f5)

    SUBJECT="$UDIR contains directories with very large numbers of files"

    MESSAGE=`cat << EOF
Hi %%NAME%%,\n
.\n
We noticed you have directories under $UDIR that have thousands of files in them.\n
.\n
For Example:\n
.\n
.      $ERROR_DIR contains $DIR_NUM files\n
.\n
.To see a complete list of directories containing large numbers of files\n
.run the following on a barrine login node.\n
.\n
.      /usr/local/bin/lsdircount.sh $VOLUME\n
.\n
PANASAS filesystems work best for a small number of large files. \n
Performance is impacted when accessing directories containing large \n
numbers of small files.\n
You may have noticed this already when you try to access these directories.\n
.\n
Please consider compressing or removing the files in these directories.\n
.\n
/work1, /work2 and /home are not for long term storage of files\n
and are not backed up. They are for compute work only.\n
.\n
Regards\n
RCC Admin\n
\n
EOF
`
  elif [ "${ERROR_TYPE}" = "MAXFILESLIMIT" ]
  then
    FILE_NUM=$(echo "$error" | cut -d\: -f5)

    SUBJECT="$UDIR is over quota for total number of files ($FILE_NUM)"

    MESSAGE=`cat << EOF
Hi %%NAME%%,\n
.\n
We noticed your $UDIR directory contains $FILE_NUM files.\n
This is significantly over quota.\n
.\n
PANASAS filesystems work best for a small number of large files. \n
Performance is impacted when accessing directories containing large\n 
numbers of small files.\n
.\n
You may have noticed this already when trying to access these directories.\n
.\n
Please consider compressing or removing some files.\n
.\n
As a reminder, /work1, /work2 and /home are not for long term storage of\n
files and are not backed up. They are for compute work only.\n
.\n
Regards\n
RCC Admin\n
EOF
`
 else
   continue
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

if [ $STATUS_CODE -ne 200 ]
then
  echo "ERROR: $TO_USER $STATUS_CODE" >&2
fi


}

# ---------------------------------------------------------------------------

APANPATH="${VOLUME}/.apandu"

RDATE=`date -d date -d today +%Y-%m-%d`
ERR_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.ER"

if [ ! -e "$ERR_FILE" ]
then
  RDATE=`date -d date -d yesterday +%Y-%m-%d`
  ERR_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.ER"
  if [ ! -e "$ERR_FILE" ]
  then
    echo "ERROR: apan_du.sh has not been run the last day or two" >&2
    exit 1
  fi
fi

if ! grep -q "^END:" "$ERR_FILE"
then
  echo "ERROR: apan_du.sh has not finished running or was terminated." >&2
  exit 1
fi

cat $ERR_FILE | while read e
do
  if [ ! -n "${e}" ]; then continue; fi

  if [ "${e}" != "${e/START/}" ]; then continue; fi
  if [ "${e}" != "${e/END:/}" ]; then continue; fi
  if [ "${e}" != "${e/pan_du:/}" ]; then continue; fi

  processerror "$e"
  sleep 5
done

