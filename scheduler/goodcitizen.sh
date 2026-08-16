#!/bin/bash
#---------------------------------------------------------------------------
# @(#)$Id$
#title          :goodcitizen.sh
#description    :Script to email users using 100% cpu for more than 1 hour
#author         :Danny W Sheehan
#date           :July 2014
#website        :www.setuptips.com
#
# This script is meant to run as a cron job on head nodes every 2 hours.
# It sends an email to users using > 80% cpu for more than 1 hour.
#
# It also checks for users calling PBS/Torque qstat with the watch command,
# thereby potentially overloading the PBS/Torque scheduler.
#
# Comment this section of code out if you don't need it.
#
# It keeps a record of offenders and will only mail them once.
#---------------------------------------------------------------------------
# 
FROM='admin@headnode'

BHOST=`uname -n`

THISUE="/tmp/headnode-user-education$$.txt"
LASTUE="/tmp/headnode-user-education.txt"

LASTUSER=""

touch $THISUE
touch $LASTUE

#
# check for users continually polling qstat with watch.
#
ps -eo user,pid,command | \
  grep " watch " | grep "qstat" | awk '{ print $0 }' | sort | while read u
do
 USERN=`echo $u | awk '{print $1}'`
 USERP=`echo $u | awk '{print $2}'`
 WATCH_N=`echo $u | sed -e "s/^.* \-n \([0-9]*\) .*$/\1/"`
 if [ $WATCH_N -lt 60 ]
 then

   # Only real users, and only notify user of first process found 
   # - Leave it up to them to identify other high cpu scripts they are running.
   uidnum=`getent passwd $USERN | awk -F: '{print $3}'`
   if [ $uidnum -gt 1000 ] && [ "${LASTUSER}" != "${USERN}" ]
   then
     LASTUSER=$USERN

     gcos=`getent passwd $USERN | awk -F: '{print $5}'`

     # Don't mail the user if you already mailed them the last time.
     egrep -q "^QSTAT ${USERN} " $LASTUE
     if [ $? -eq 0 ]
     then 
       echo "QSTAT $u $gcos" >> $THISUE
     else
       TO_USER=$USERN 
       echo "mailing $USERN" 
     MESSAGE=`cat << EOF
Hi %%NAME%%,\n
.\n
We noticed you are calling qstat excessively with the watch command\n
.\n
 $u \n
.\n
Please select watch -n values > 120 seconds, as selecting -n values\n
any less just slows down the PBS scheduler and wastes resources\n
.\n
Regards\n
HPC admin\n
EOF
`

     echo $MESSAGE | mail -r $FROM \
         -s "You are calling qstat excessively on a headnode login node" \
         $TO_USER
    fi
  fi
 fi
done


LASTUSER=""
ps -eo user,pid,pcpu,etime,command | \
 awk '{ if ($3 > 80 && ( $4 ~ /^[0-9][1-9]:/ || $4 ~ /\-/ ) ) print $1,$2,$3,$4,$5 }' | sort | while read u
do

 # user xxxx pid= 12268 cpu%= 10.5 for 02:23:35 command= sshd:

 USERN=`echo $u | awk '{print $1}'`
 USERP=`echo $u | awk '{print $2}'`
 USERC=`echo $u | awk '{print $3}'`
 USERT=`echo $u | awk '{print $4}'`
 USERA=`echo $u | awk '{print $5}'`

 # qsub/rsync are ok to run
 echo $USERA | egrep -q "(qsub|rsync)"
 if [ $? -ne 0 ]
 then

   # Only non system users and don't email user twice.
   uidnum=`getent passwd $USERN | awk -F: '{print $3}'`
   if [ $uidnum -gt 1000 ] && [ "${LASTUSER}" != "${USERN}" ]
   then
  
     LASTUSER=$USERN
  
     gcos=`getent passwd $USERN | awk -F: '{print $5}'`
   
  
     # Don't mail the user if you already mailed them the last time.
     egrep -q "^CPUHOG ${USERN} " $LASTUE
     if [ $? -eq 0 ]
     then 
       echo "CPUHOG $u $gcos" >> $THISUE
     else
       TO_USER=$USERN 
       echo "mailing $USERN" 
       MESSAGE=`cat << EOF
Hi %%NAME%%,\n
.\n
It looks like you are doing some compute work $USERA - pid $USERP on the $BHOST \n
login node. Please immediately kill your $USERA processes. There may be other\n
processes as well. Use the 'top -u $USERN' command to identify any other\n
high %CPU usage processes.\n
.\n
I want to remind you about interactive PBS sessions ($ qsub -I), as the\n
login nodes shouldn't be used for compute tasks as they are a shared\n
resource. We strongly encourage everyone to compile, test out programs and\n
do post-processing of results, as with their main processing, on one of\n
the compute nodes. In this case you will probably want to use one of the\n
compute nodes interactively through the PBS batch system:\n
.\n
$ qsub -I -l select=1:ncpus=1:mem=2gb -l walltime=6:0:0 -A\n
your_accounting_id\n
.\n
This will take your shell to one of the compute nodes and everything else\n
should behave just like you're on headnode. You can even use graphical (X)\n
applications on the compute nodes through PBS by adding the -v DISPLAY option.\n
.\n
If you need a node quickly, for a short time, you can use the interactive\n
queue.\n
.\n
qsub -I -v DISPLAY -l select=1:ncpus=1:mem=2gb -l walltime=3:0:0 -q interact -A\n
your_accounting_id\n
.\n
This is a machine generated message, but a ticket is generated so you can reply with questions for support staff.\n
.\n
Regards\n
HPC Admin\n
EOF
`

echo $MESSAGE | mail -r $FROM \
         -s "You are running compute jobs directly on a headnode login node" \
         $TO_USER
      fi
    fi
  fi
done

mv $THISUE $LASTUE
