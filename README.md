HPC-Scripts
===========

Scripts to help Unix Administrators manage High Performance Computing (HPC) environments.


## HPC Head Node Scripts

In a typical HPC environment users login to _head nodes_ also referred to a
_login nodes_ , from where they submit their batch jobs.


### HPC Head Node Abuse Detection (_goodcitizen.sh_)

Sometimes users run CPU intensive jobs on the head nodes rather than submitting
batch jobs to PBS/Torque.  

The _goodcitizen.sh_ script detects users who are running CPU intensive jobs 
and notifies them via email to use interactive batch jobs instead.

Other checks can be added, for example:

_"watch qstat" detection_  - users sometimes overload the PBS/Torque scheduler 
by continually polling the status of their jobs with _watch qstat_.

For more details on configuration see [goodcitizen](goodcitizen.md).
