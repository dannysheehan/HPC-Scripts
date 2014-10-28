#!/bin/bash
# ------------------------------------------------------------------------
# compress-job-output-files.sh finds .o and .e PBS job output files in current 
# directory and compress them into tar files, and then removes them.
#
# BACKGROUND
# PANASAS and NFS file systems are very inefficient when dealing with
# directories containing thousands of small files.  When users access these
# directories (e.g. ls) major impacts to performance occur as a result.
#
# This is usally caused when users use array jobs that generate a separate
# .o and .e file for each sub job. Whith 10k+ index job arrays this can
# get out of hand and can soon escalate into a catch 22 situation where users
# are unable to remove or even tar up the files because of the directory 
# access performance issue.
#
# compress-job-output-files gets around this issue by chunking up access
# to the files based on the job index so that a tar/removal can be performed. 
#
# users can later retrieve the output files from the tar files that are 
# created.
# ------------------------------------------------------------------------

for j in `ls -1 *.o[0-9][0-9][0-9][0-9][0-9][0-9][0-9].1`
do
  echo $j
  JOBN=`basename $j .1`
  for i in {1..9}
  do
    echo $i
    tar -czf ${JOBN}.bkp.${i}.tar.gz ${JOBN}.${i}*
    rm ${JOBN}.${i}*
  done
done

for j in `ls -1 *.e[0-9][0-9][0-9][0-9][0-9][0-9][0-9].1`
do
  echo $j
  JOBN=`basename $j .1`
  for i in {1..9}
  do
    echo $i
    tar -czf ${JOBN}.bkp.${i}.tar.gz ${JOBN}.${i}*
    rm ${JOBN}.${i}*
  done
done
