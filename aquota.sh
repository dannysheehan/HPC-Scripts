#!/bin/bash
#
BHOST=`uname -n`

VOLUME="$1"

DU_LIMIT_G=200
FILE_LIMIT=1000

if [ -n "$2" ] && [[ $2 =~ ^[0-9]+$ ]]
then
  DU_LIMIT_G="$2"
fi

if [ -n "$3" ] && [[ $3 =~ ^[0-9]+$ ]]
then
  FILE_LIMIT="$3"
fi

# -------------------------
processdu() {
  duinfo="$1"

  UNAME=$(echo "$duinfo" | cut -d\, -f1)
  UDIR=$(echo "$duinfo" | cut -d\, -f3)
  DUSIZE=$(echo "$duinfo" | cut -d\, -f4)
  FILESNUM=$(echo "$duinfo" | cut -d\, -f5)
  TO_USER=$UNAME

  if [ $DUSIZE -gt $DU_LIMIT_G ]
  then
    echo "********************"
    echo "**ACTION REQUIIRED**"
    echo "********************"
    echo " - Your $UDIR disk usage on barrine ($DUSIZE GB) is greater than the $DU_LIMIT_G GB quota limit."
    echo " - Please archive/compress/remove some files or contact support"
    if [ $DUSIZE -gt 200 -a  $DUSIZE  -lt 1000 ]
    then
      echo " - Alternatively please use /work1/$USER instead"
    fi
    if groups | grep -q bioinformatics
    then
      echo " - Alternatively please use /ebi/bscratch/$USER instead"
    fi
  elif [ $FILESNUM -gt $FILE_LIMIT ]
  then
    echo "********************"
    echo "**ACTION REQUIIRED**"
    echo "********************"
    echo " - Your $UDIR files count ($FILESNUM) is greater than the quota limit of $FILE_LIMIT files per user."
    echo " - Please archive/compress/remove some files or contact support"
    if groups | grep -q bioinformatics
    then
      echo " - Alternatively please use /ebi/bscratch/$USER instead"
    fi
  fi

}


# -------------------------
processerror() {
  error="$1"

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

    echo "********************"
    echo "**ACTION REQUIIRED**"
    echo "********************"
    echo "$UDIR contains directories with a large numbers of files"
    echo " -  $ERROR_DIR has $DIR_NUM files."
    echo " - This slows down PANASAS performance."
    echo " - Please archive/compress/remove this directory or contact support for help"
    if groups | grep -q bioinformatics
    then
      echo " - Alternatively please use /ebi/bscratch/$USER instead"
    fi
  elif [ "${ERROR_TYPE}" = "MAXFILESLIMIT" ]
  then
    FILE_NUM=$(echo "$error" | cut -d\: -f5)
    echo "********************"
    echo "**ACTION REQUIIRED**"
    echo "********************"
    echo "Your $UDIR files count ($FILE_NUM) is greater than the quota of $FILE_LIMIT files per user."
    echo " - Please archive/compress/remove some files or contact support for help"
    if groups | grep -q bioinformatics
    then
      echo " - Alternatively please use /ebi/bscratch/$USER instead"
    fi
  fi
}

# ---------------------------------------------------------------------------

APANPATH="${VOLUME}/.apandu"

RDATE=$(date -d date -d today +%Y-%m-%d)
ERR_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.ER"
CSV_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.csv"

USER_FOUND=0
if [[ -e "$ERR_FILE" ]]
then
  DU_ENTRY=$(grep "$USER,"  $CSV_FILE | head -1)
  ER_ENTRY=$(grep ":${USER}:" $ERR_FILE | head -1)
  if [ -n "${DU_ENTRY}" ] || [ -n "${ER_ENTRY}" ]
  then
    USER_FOUND=1
  fi
fi

if (( ! $USER_FOUND ))
then
  RDATE=$(date -d date -d yesterday +%Y-%m-%d)
  ERR_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.ER"
  CSV_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.csv"
  if [[ -e "$ERR_FILE" ]]
  then
    DU_ENTRY=$(grep "$USER,"  $CSV_FILE | head -1)
    ER_ENTRY=$(grep ":${USER}:" $ERR_FILE | head -1)
    if [ -n "${DU_ENTRY}" ] || [ -n "${ER_ENTRY}" ]
    then
      USER_FOUND=1
    fi
  fi
fi

if (( ! $USER_FOUND ))
then
  RDATE=$(date -d date -d "2 day ago" +%Y-%m-%d)
  ERR_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.ER"
  CSV_FILE="${APANPATH}/PanasasUsageReport_${RDATE}.csv"
  if [[ -e "$ERR_FILE" ]]
  then
    DU_ENTRY=$(grep "$USER,"  $CSV_FILE | head -1)
    ER_ENTRY=$(grep ":${USER}:" $ERR_FILE | head -1)
    if [ -n "${DU_ENTRY}" ] || [ -n "${ER_ENTRY}" ]
    then
      USER_FOUND=1
    fi
  fi
fi

echo
if (( ! $USER_FOUND ))
then
  echo "No $VOLUME quota data found for $USER"
  exit 1
fi

echo "$VOLUME quota last calculated on $RDATE"
if [[ -n "${DU_ENTRY}" ]]
then
  processdu "${DU_ENTRY}"
fi

if [[ -n "${ER_ENTRY}" ]]
then
  processerror "${ER_ENTRY}"
fi
