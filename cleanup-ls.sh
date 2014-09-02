#!/bin/bash
# -----------------------------------------------------------
# Lists files that will be removed or that are excpeted for
# removal from /work2 for all users or a specific
# user.
#
# USAGE
#   cleanup-ls.sh -e <directory relative to /work2>
#     - list the files that are excepted for deletion under specified directory.
#
#   cleanup-ls.sh -d <directory relative to /work2>
#     - list the files that will be removed for all users.
#
#
# -----------------------------------------------------------
FILES_TO_DELETE="/work2/CLEANUP/delete-filelist.txt"
DELETE_EXCEPTIONS="/work2/CLEANUP/delete-exceptions.txt"

TEMP_EXCEPT="/tmp/djsksksej$$"

#
# remove blank lines and comments from delete exceptions.
# they will screw things up big time.
#
sed -e "/^[ \t]*$/d" -e "/^#/d" $DELETE_EXCEPTIONS > $TEMP_EXCEPT


usage()
{ 
  echo "
Usage: $0 [-e] [-d] [bscratch sub-directory]

Lists the files that will be deleted/excepted for all bscratch directories 
or for the specified [bscratch sub-directory]

  -e  list the excepted files only. 

  -d  list the files that are not excepted and will be deleted.

[bscratch sub-directory] is relative to /work2

Example:
   $0 -d jarrah
   $0 -e jarrah/userx
   $0 -e userx

" 1>&2
  rm -f $TEMP_EXCEPT
  exit 1
}

do_user_stats=""
do_exceptions=""
while [ $# -gt 0 ]
do
        case "$1" in
        -e)   shift ; do_exceptions=y ;;
        -d)   shift ; do_exceptions=n ;;
        -s)   shift ; do_user_stats=y ;;
        -)    shift ; break ;;
        -*)   usage ;;
        *)    break ;;
        esac
done

DIRN="${1}"

DIRN=`echo $DIRN | sed -e "s/^[\.\/]*//" | sed -e "s/^/\//"`

#
# sorted statistics on counts of excepted files or removed files.
#
# HIDDEN OPTION
#
if [ -n "$do_user_stats" ]
then

  if [ "$do_exceptions" = "y" ]
  then
   echo "--- Directories with exceptions and associated exception file counts ---"
   echo "NOTE: some exceptions could be on sub-directories"
   echo
   grep -z -f $TEMP_EXCEPT  $FILES_TO_DELETE | \
      awk -F\/ 'BEGIN { RS="\0"; } { printf "%s\n", $3 }' - | uniq -c | sort -n 
  elif [  "$do_exceptions" = "n" ]
  then
   echo "--- Directories without exceptions and associated removal file counts ---"
   echo "NOTE: some exceptions could be on sub-directories"
   echo
   grep -z -v  -f $TEMP_EXCEPT  $FILES_TO_DELETE | \
      awk -F\/ 'BEGIN { RS="\0"; } { printf "%s\n", $3 }' - | uniq -c | sort -n
  fi
  exit 0
fi


if [ "$do_exceptions" = "y" ]
then
  grep -z $DIRN $FILES_TO_DELETE |  grep -z -f $TEMP_EXCEPT | xargs -l1 -0

elif [  "$do_exceptions" = "n" ]
then
  grep -z $DIRN $FILES_TO_DELETE | grep -z -v -f $TEMP_EXCEPT | xargs -l1 -0
else
  usage
fi

rm -f $TEMP_EXCEPT
