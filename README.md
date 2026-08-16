# HPC-Scripts

Scripts for Unix admins and users running HPC environments. Changes go on a branch and land on `main` through a pull request.

## Layout

| Directory | What |
| --- | --- |
| [cleanup/](cleanup/) | Expire unused scratch and `/tmp` files |
| [storage/](storage/) | Disk usage, quotas, volume fill rate |
| [hsm/](hsm/) | HSM / tape backups of small files |
| [scheduler/](scheduler/) | Head-node and PBS/Torque checks |

## cleanup

### expirefiles.py

Scratch filesystems fill up because users leave data that is not backed up. `expirefiles.py` finds files not accessed in N days, can email owners, and can delete. User and path exceptions are supported.

Details: [expirefiles.md](cleanup/expirefiles.md)

### cleantmp.sh

Removes `/tmp` files not accessed in 2 days that are not open and whose owner has no running processes.

## storage

### apan_du.sh / apan_du_notify.sh / lsdircount.sh

PANASAS usage. `apan_du.sh` wraps `pan_du` and flags directories with too many files. `apan_du_notify.sh` emails (and can throttle) users over a GB limit. `lsdircount.sh` reports directories over the file-count limit from the last `apan_du` run.

### aquota.sh / rquota

Quota notices. `aquota.sh` warns PANASAS users over size or file limits. `rquota` prints GPFS home/scratch/group quota via `mmlsquota`.

### user-disk-usage.sh / volfillrate.sh

`user-disk-usage.sh` walks a tree and records per-owner usage. `volfillrate.sh` samples `df` to estimate how fast a volume is filling.

## hsm

### chunkybackup.sh

Splits a directory into sized tar chunks on HSM so small files actually go to tape. Run as the data owner, not root.

Details: [chunkybackup.md](hsm/chunkybackup.md)

### dpart.sh / hsync.sh

`dpart.sh` wraps `fpart` to chunk by directory size. `hsync.sh` rsyncs those chunks, waiting on HSM to stage files.

## scheduler

### goodcitizen.sh

Cron on head nodes. Emails users pegging CPU for more than an hour, and catches `watch qstat`.

Details: [goodcitizen.md](scheduler/goodcitizen.md)

### pbsqcheck.sh / usage-check.sh / dynamic-motd.sh

`pbsqcheck.sh` summarises queued PBS jobs. `usage-check.sh` warns if load is more than 2× CPU count. `dynamic-motd.sh` is a small MOTD helper.
