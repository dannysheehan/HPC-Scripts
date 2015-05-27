HPC-Scripts
===========

Scripts to help Unix Administrators and Users manage High Performance Computing (HPC) environments.

## HPC Cleanup Scripts

### Scratch Filesystem Cleanup (_expirfiles.py_)

HPC systems have very large fast parallel filesystems where users 
can generate and use literally terrabytes of data during computation.
- "scratch" filesystems.
Unfortunately, users to tend to leave files around in these filesystems
rather than backing them up to long term storage such as HSM.
Quotering can get around this issue, but can still results in people leaving
uneeded files around and hogging space.
Also, since "scratch" filesystems are typically not backed up, the practice of 
leaving files in "scratch" filesystems is not safe.

Given a file system _expirefiles_ will find all files that have not been
accessed in a specified number of days. It has options to warn users
of files which are about to be expired (removed) via email.

Exceptions for usernames and also file paths are supported, where certain
files can be exempted from a later deletion.

For more details see [expirefiles](expirefiles.md).


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

## HPC Hierarchical Storage Management (HSM) Scripts

Most HSM facilities using HSM storage management. This usually consists of
a quota based NFS **online** frontend disk cache to a much larger backend
**offline** tape component.  Users copy data to the cache and the HSM offlines
the data in the background. 


### HSM Chunk Small Files Into Large Files (_chunkybackup.sh_)

As can be expected copying lots of small files to HSM storage is not 
particularly efficient. Small files are typically not big enough to be
automatically moved to tape and will remain forever in the cache. This is
why _chunkybackup.sh_ was written to allow users of a HPC faility to 
easily "chunk up" their smaller data files.

For more details see [chunkybackup](chunkybackup.md).



[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/dannysheehan/hpc-scripts/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

