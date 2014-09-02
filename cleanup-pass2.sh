#!/bin/bash
#
# This script is intented to warn users of $FS_NAME $NOTIFY_DAYS days ahead of
# time that files that they have not accessed for more then $LAST_ACCESS days 
# will be deleted.
#
# WARNING: This script will mass email users.
# 
# USAGE
#   cleanup-pass2.sh  <user>
#     - will just notify the specified user
#
#   cleanup-pass2.sh 
#     - will notify ALL users. 
#  
# Must run on head node in order for users to receive emails.
#
# DEPENDENCY
#   cleanup-pass1.sh must have run previously
# -------------------------------------------------------------------------

# The filesystem we are performing housekeeping (cleanup) on.
FS_NAME="/scratch365"

# Just for testing
FS_NAME="/home/$USER"

# The minimum last access time for which users files will be deleted.
LAST_ACCESS=365

# How much warning we are going to give users that their files will be deleted.
NOTIFY_DAYS_DEFAULT=14

# Who to send summary statistics to.
MAIL_ADMIN='admins@hpc'

# Who the emails are from.
FROM='support@hpc'
FROM_NAME='HPC Support'


CLEANUP_HOME="${FS_NAME}/CLEANUP"

FILES_TO_DELETE="$CLEANUP_HOME/delete-filelist.txt"
DELETE_EXCEPTIONS="$CLEANUP_HOME/delete-exceptions.txt"
CLEANUP_LS_CMD="$CLEANUP_HOME/$FS_NAME-ls.sh"

#
# projects house user directories underneath a subdirectory of $FS_NAME
# e.g. /projecta/|/porjectx/
# /projecta/userx
# /projecta/usery
PROJECT_DIRS="/projectx/|/projecty/"


NOTIFY_DAYS=$NOTIFY_DAYS_DEFAULT
TEMP_EXCEPT="/tmp/kkjej$$"


usage()
{
  echo "
usage: $0 [-n days] [user]

Notifies all users of time to deletion or if they have an exception in
place.

  -n days  number of days to deletion notification length.

  [user]   if specified just notify that user
           if not specified notify all users (dangerous)
" 1>&2
  exit 1;
}

while [ $# -gt 0 ]
do
        case "$1" in
        -n)   shift ; NOTIFY_DAYS=$1; shift;;
        -)    shift ; break ;;
        -*)   usage ;;
        *)    break ;;
        esac
done

NOTIFY_USER="$1"

if [ -n "$NOTIFY_USER" ]
then
  echo "Notifying $NOTIFY_USER of deletion in $NOTIFY_DAYS days & if they have exceptions."
  echo ".. this may take some time"
fi


# OPTIONAL: Some extra checks
# we can notify individual users any time after the files to be deleted are 
# generated, but we must notify *all* users ONLY for recent (2 days old) 
# files-to-delete generation.
#
ADMIN_MESSAGE_1="Users notifed of $FS_NAME cleanup in $NOTIFY_DAYS days"
if [ -z "$NOTIFY_USER" -a $NOTIFY_DAYS -eq $NOTIFY_DAYS_DEFAULT ]
then
  if [[ $(date +%s -r $FILES_TO_DELETE) -lt $(date +%s --date="2 day ago") ]]
  then
     echo "$FILES_TO_DELETE needs to be regenerated. It is over 2 days old" | \
        mail -s "ERROR: $0 " $MAIL_ADMIN
     exit 1
  fi
else
  ADMIN_MESSAGE_1="User $NOTIFY_USER notifed of $FS_NAME cleanup in $NOTIFY_DAYS days or about their exceptions."
fi

if [ ! -e "$FILES_TO_DELETE" ]
then
   echo "$FILES_TO_DELETE does not exist" | \
      mail -s "ERROR: $0 " $MAIL_ADMIN
   exit 2
fi

if [ ! -e "$DELETE_EXCEPTIONS" ]
then
   echo "$DELETE_EXCEPTIONS does not exist" | \
      mail -s "ERROR: $0 " $MAIL_ADMIN
   exit 3
fi

#
# remove blank lines and comments from delete exceptions.
# they will screw things up big time.
#
sed -e "/^[ \t]*$/d" -e "/^#/d" $DELETE_EXCEPTIONS > $TEMP_EXCEPT

#
# Notify users about their exceptions
# -----------------------------------
for levels2 in `grep -z -f $TEMP_EXCEPT  $FILES_TO_DELETE | \
    awk -F\/ 'BEGIN { RS="\0"; } { printf "%s/%s\n", $3,$4 }' - | sort | uniq`
do
   next_level="$FS_NAME/$levels2"

   if [ -e "$next_level" ]
   then
     top_level=`dirname $next_level`
     if [ -d $top_level ] && [ $top_level != "$FS_NAME" ]
     then
       # Projects have their own home directory base - which complicates things.
       if echo $next_level | egrep -q $PROJECT_DIRS 2> /dev/null
       then
         OWNER=`stat -c "%U" $next_level`
         FILEN=`stat -c "%n" $next_level`
       else
         OWNER=`stat -c "%U" $top_level`
         FILEN=`stat -c "%n" $top_level`
       fi
       echo "$OWNER $FILEN"
     fi
   fi
   
done | sort | uniq | egrep "^${NOTIFY_USER}" | sed -e "/^[ \t]*$/d" | while read d
do
  OWNER_DIRECTORY=`echo $d | awk '{print $2}'`
  OWNER_DIRECTORY=${OWNER_DIRECTORY#$FS_NAME}

  OWNER=`echo $d | awk '{print $1}'`
  GCOS=`getent passwd $OWNER | awk -F: '{print $5}'`

       echo "
Hi $GCOS,

This is a system generated message.

You have files that have not been accessed for over $LAST_ACCESS days under
${FS_NAME}${OWNER_DIRECTORY}.

You have an exception in place for some or all of these files:
   see $DELETE_EXCEPTIONS

For a list of your files that have been excepted, enter the following command 
on a HPC login node.

   ${CLEANUP_LS_CMD} -e '$OWNER_DIRECTORY/'

Please notify $FROM if you no longer need this exception, or please help to 
clean up files you no longer need.

Regards
$FROM_NAME
$FROM
" | mail -r $FROM \
   -s "Your ${FS_NAME}${OWNER_DIRECTORY} deletion exception" \
  $OWNER
  
  # sleep between sending emails so we don't get blocked for sending too
  # many emails at once.
  sleep 30
done 


#
# Notify users about their pending deletions.
# -------------------------------------------
#
for levels2 in `grep -z -v -f $TEMP_EXCEPT $FILES_TO_DELETE | \
    awk -F\/ 'BEGIN { RS="\0"; } { printf "%s/%s\n", $3,$4 }' - | sort | uniq`
do
   next_level="$FS_NAME/$levels2"
   if [ -e "$next_level" ]
   then
     top_level=`dirname $next_level`
     if [ -d $top_level ] && [ $top_level != "$FS_NAME" ]
     then
       # projects have their own home directory base - which complicates things.
       if echo $next_level | egrep -q $PROJECT_DIRS 2> /dev/null
       then
         OWNER=`stat -c "%U" $next_level`
         FILEN=`stat -c "%n" $next_level`
       else
         OWNER=`stat -c "%U" $top_level`
         FILEN=`stat -c "%n" $top_level`
       fi
       echo "$OWNER $FILEN"
     fi
   fi
   
done | sort | uniq | grep "^${NOTIFY_USER}" | sed -e "/^[ \t]*$/d"  | while read d
do
  OWNER_DIRECTORY=`echo $d | awk '{print $2}'`
  OWNER_DIRECTORY=${OWNER_DIRECTORY#$FS_NAME}

  OWNER=`echo $d | awk '{print $1}'`
  GCOS=`getent passwd $OWNER | awk -F: '{print $5}'`

# OWNER='uqdshee2'

       echo "
Hi $GCOS,

This is a system generated message.

You have files that have not been accessed for over $LAST_ACCESS days under
${FS_NAME}${OWNER_DIRECTORY}.

Please backup any files you wish to keep or notify $FROM to arrange an exception.

For a list of your files that will be deleted type the following command on a HPC login node.

   ${CLEANUP_LS_CMD} -d '$OWNER_DIRECTORY/'

These files will be deleted in $NOTIFY_DAYS days if you do not access them.

To view the last access time of a file you can use the following.

   ls -lud <filename>


Regards
$FROM_NAME
$FROM
" | mail -r $FROM \
   -s "Your ${FS_NAME}${OWNER_DIRECTORY} files not accessed in $LAST_ACCESS days will be deleted in $NOTIFY_DAYS days time." \
  $OWNER

  # sleep between sending emails so we don't get blocked for sending too
  # many emails at once.
  sleep 30
  echo $d
done | mail -r $FROM -s "$ADMIN_MESSAGE_1" $MAIL_ADMIN

#
# Summary statistics for administrators.
#
if [ -z  "$NOTIFY_USER" ]
then
  $CLEANUP_LS_CMD -s -d | \
     mail -r $FROM -s "$FS_NAME counts of files to be deleted in $NOTIFY_DAYS days" $MAIL_ADMIN

  $CLEANUP_LS_CMD -s -e | \
     mail -r $FROM -s "$FS_NAME counts of files excepted from deletion in $NOTIFY_DAYS days" $MAIL_ADMIN
fi


rm -f $TEMP_EXCEPT
