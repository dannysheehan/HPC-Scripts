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
#./pbsqcheck.sh: line 66: 160 / 
#16:ncpus=2:NodeType=medium:mem=10GB:mpiprocs=2: :

echo "   WAIT_DAYS JOB_ID NODES NODETYPE MEM (MEMSET) CPU_HRS / NCPUS = WALLTIME" 
QTIMESTR=""
qstat -f `qselect -sQ` | \
  egrep "(qtime|Resource_List.select|Resource_List.mem|Job Id:|Resource_List.cpu_hrs|Resource_List.ncpus|Submit_arguments)" | \
     while read l
do
  ADMIN_MSG=`qstat -s $JOB_ID 2> /dev/null | tail -1 | awk -F\: '{print $2}' | grep -v "too few free"`
  ANYNODE=""

  if [  "${l}" != "${l/Job Id:/}" ]
  then
    JOB_ID=`echo $l | awk '{print $3}'`

  elif [ "${l}" != "${l/Resource_List.mem/}" ]
  then
    MEM=`echo $l | awk '{print $3}'`
    if [ "${MEM}" != "${MEM/mb/}" ]
    then
      MEM=${MEM/mb/}
      if [ $MEM -gt 1000 ]
      then
        MEM=`echo "scale=0;$MEM / 1000" | bc -l`
      else
        MEM=1
      fi
    fi
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
    SELECT=`echo $l | awk '{print $3}' | sed -e "s/:sched.*//"`
    NODES=`echo $SELECT | tr ':' '\n' | head -1`
    NODETYPE=`echo $l | tr ':' '\n' | grep "NodeType=" | cut -d\= -f2`
    MEMSET=`echo $l | tr ':' '\n' | grep "mem=" | cut -d\= -f2`
    NCPUSET=`echo $l | tr ':' '\n' | grep "ncpus=" | cut -d\= -f2`

    if [ -n "$QTIMESTR" ]
    then
      QTIME=$(date -d "$QTIMESTR" "+%s")
      NOW=$(date -d "now" "+%s")
      WAIT_TIME=$(( ($NOW - $QTIME) / 60 / 60 / 24 ))
    fi


  elif [  "${l}" != "${l/Submit_arguments/}" ]
  then
    ANYNODE=`echo $l | grep -i "NodeType=any"`

    WALLTIME=$(( $CPU_HRS / $NCPUS ))

    if [ "${MEM}" != "${MEM/[0-9]*/}" ]
    then
      MEM=$((  $MEM / $NODES )) 
    fi

    QTIMESTR=""
    if [ -z "$MEM" ]
    then
      echo ">> $JOB_ID did not specify mem:"
      echo "   $WAIT_TIME $JOB_ID $NODES $NODETYPE $MEM ($MEMSET) $CPU_HRS / $NCPUS = $WALLTIME" 
      #if [ -n "${ADMIN_MSG}" ]; then echo "    '$ADMIN_MSG'";fi 
      #    echo "    select=$SELECT"
    fi

    echo "   $WAIT_TIME $JOB_ID $NODES $NODETYPE $MEM ($MEMSET) $CPU_HRS / $NCPUS = $WALLTIME" 
    if [ -n "${ADMIN_MSG}" ]; then echo "    '$ADMIN_MSG'";fi 
    continue

    if [ -z "$NODETYPE" ] && [ $WALLTIME -lt 24 ]
    then
      echo ">> $JOB_ID specified nodetype any with $WALLTIME < 24 hrs"
      echo "   $WAIT_TIME $JOB_ID $NODES $NODETYPE $MEM ($MEMSET) $CPU_HRS / $NCPUS = $WALLTIME" 
    fi

    if [ "$NODETYPE" = "xl" ] && [ $MEM -lt 71 ]
    then
      echo ">> $JOB_ID specified nodetype xl with $MEM < 71g"
      echo "   $WAIT_TIME $JOB_ID $NODES $NODETYPE $MEM ($MEMSET) $CPU_HRS / $NCPUS = $WALLTIME" 
    fi

    if [ "$NODETYPE" = "xl" ] && [ $MEM -gt 1000 ]
    then
      echo ">> $JOB_ID specified nodetype xl with $MEM > 1000g"
      echo "   $WAIT_TIME $JOB_ID $NODES $NODETYPE $MEM ($MEMSET) $CPU_HRS / $NCPUS = $WALLTIME" 
    fi

    if [ "$NODETYPE" = "medium" ] && [ $MEM -gt 22 ]
    then
      echo ">> $JOB_ID specified nodetype medim with $MEM > 22g"
      echo "   $WAIT_TIME $JOB_ID $NODES $NODETYPE $MEM ($MEMSET) $CPU_HRS / $NCPUS = $WALLTIME" 
    fi

    if [ "$NODETYPE" = "large" ] && [ $MEM -lt 23 ]
    then
      echo ">> $JOB_ID specified nodetype large with $MEM < 23g"
      echo "   $WAIT_TIME $JOB_ID $NODES $NODETYPE $MEM ($MEMSET) $CPU_HRS / $NCPUS = $WALLTIME" 
    fi

    if [ "$NODETYPE" = "large" ] && [ $MEM -gt 70 ]
    then
      echo ">> $JOB_ID specified nodetype large with $MEM > 70g"
      echo "   $WAIT_TIME $JOB_ID $NODES $NODETYPE $MEM ($MEMSET) $CPU_HRS / $NCPUS = $WALLTIME" 
    fi

  fi
done

echo "Free xl"
echo "-------"
pbsnodes2 -1 -e jobs -e NodeType -e comment | grep "NodeType:xl" | grep -v jobs

echo
echo "Free large"
echo "----------"
pbsnodes2 -1 -e jobs -e NodeType -e comment | grep "NodeType:large" | grep -v jobs | grep -v comment

