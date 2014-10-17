cleanup-pass-x.sh
=================

This is a collection of 3 scripts meant to run from cron to cleanup
files in a given filesystem that users have not accessed in 'X' days.

It includes a special phase 2 where users are notified that they have
'Y' days to backup or access their files before they are removed.

It includes an exception mechanism where users can request that 
certain directories be excepted for deletion.

## Pass 1 - find the files
- cleanup-pass1.sh

## Pass 2 - notify the users Y days ahead of deletion that their files
are to be deleted
- cleanup-pass2.sh -n Y

## Pass 3 - remove the files that have not been accessed in X days
- cleanup-pass3.sh


## Helper Script
- cleanup-ls.sh
- the *files to be delete* are kept in binary format so the *cleanup-ls.sh*
helper script provides a way to list the files to be deleted in human 
readable form.
