chunkybackup.sh
===============

**chunkybackup.sh directory backup-file chunksize**

This script backups up the specified _directory_ across N number of tar 
files of size _chunksize_. The tar files are named _backup-file.x.tgz_ 
where x is from 1..N, and are created in the users _HSM/username_ directory.

- **directory**   = directory to backup
- **backup-file** = name to use on backup files e.g. <backup-file>.1.tgz
- **chunk-size**  = the maximim chunk size for each tar file in GB

**NOTE:** Must be run as the user whose data is being backed up, not as root.

~~~
$ chunkybackup.sh /home/user home_backup 20
~~~

This script is also intended to overcome the quota limits on /HSM storage
in cases where users want to backup /home or other work data areas in
excess of their quota limits.

It is also intended to deal with cases where users have lots of small files
they want to backup to tape.

The script is fairly robust. If interrupted and restarted it will continue 
the backup from where it left off (to the nearest chunk) by first verifying 
what files have already been backed up. 

**ASSUMPTION:** No files were added since the backup was interrupted.


## ENV variables used
- **$USER** -- user running script
- **$HOST** -- node that this script is running on.
- **$TMPDIR** -- if run from batch job

_backup-file.x.tgz.txt_ files are also created under _HSM/username_ so 
users can quickly determine which tar file a paticular file or directory is 
located in.

Script uses _$SCRATCH_DIR_ as a temporary staging area, and uses dmput to 
migrate each chunk to tape. When quota is reached the script sleeps until 
the tape drives catch up and quota usages goes down. 
This overcomes the HSM quota limit.

To avoid corrupt backups, checks are made of the available space in 
_$SCRATCH_DIR_ before tar files are created,  checks of the users quota in 
_/HSM/username_ before the tar files are copied in, and the copied chunks 
are verified before chunks are written to tape.


## Sources

1. [Appending Files To Tar](http://tiamat.name/blogposts/fast-appending-files-to-tar-archive-is-impossible/)
