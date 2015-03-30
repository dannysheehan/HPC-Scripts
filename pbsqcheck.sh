#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :pbsqcheck.sh
#description    :Framework for checking jobs in Altair PBS job queue
#author         :Danny W Sheehan
#date           :March 2015
#
#  Usage: 
#
# --------------------------------------------------------------------------
QTIMESTR=""
qstat -f `qselect -sQ` | \
  egrep "(qtime|Resource_List.select|Resource_List.mem|Job Id:|Resource_List.cpu_hrs|Resource_List.ncpus)" | \
     while read l
do

  if [  "${l}" != "${l/Job Id:/}" ]
  then
    JOB_ID=`echo $l | awk '{print $3}'`

  elif [ "${l}" != "${l/Resource_List.mem/}" ]
  then
    MEM=`echo $l | awk '{print $3}'`
    MEM=${MEM/gb/}

  elif [ "${l}" != "${l/Resource_List.cpu_hrs/}" ]
  then
    CPU_HRS=`echo $l | awk '{print $3}'`

  elif [ "${l}" != "${l/Resource_List.ncpus/}" ]
  then
    NCPUS=`echo $l | awk '{print $3}'`

  elif [ "${l}" != "${l/qtime/}" ]
  then
    QTIMESTR=`echo $l | awk -F\= '{print $2}' | sed -e "s/^ //"`

  elif [ "${l}" != "${l/Resource_List.select/}" ]
  then
    SELECT=`echo $l | awk '{print $3}' | sed -e "s/:sche.*$/:/"`
    NODETYPE=`echo $SELECT | sed -e "s/^.*:NodeType=\([^:]*\):.*$/\1/"` 
    if [ "$NODETYPE" = "$SELECT" ]
    then
       NODETYPE="none"
    fi
    NODES=`echo $SELECT | sed -e "s/^\([0-9]\):.*$/\1/"`
    MEMSET=`echo $SELECT | sed -e "s/^.*:mem=\([0-9GgmbB]*\):.*$/\1/"` 
    if [ "$MEMSET" = "$SELECT" ]
    then
       MEMSET="none"
       continue
    fi

    if [ -n "$QTIMESTR" ]
    then
      QTIME=$(date -d "$QTIMESTR" "+%s")
      NOW=$(date -d "now" "+%s")
      WAIT_TIME=$(( ($NOW - $QTIME) / 60 / 60 / 24 ))
    fi

    ADMIN_MSG=`qstat -s $JOB_ID | tail -1 | awk -F\: '{print $2}' | grep -v "too few free"`
   
    if [ "${MEM}" != "${MEM/[0-9]*/}" ]
    then
      MEM=$((  $MEM / $NODES )) 
    fi
    echo "$WAIT_TIME $JOB_ID $NODES $NODETYPE $MEM ($MEMSET) $NCPUS $CPU_HRS"
    if [ -n "${ADMIN_MSG}" ]; then echo "    '$ADMIN_MSG'";fi 
        echo "    select=$SELECT"
    QTIMESTR=""
  fi
done
