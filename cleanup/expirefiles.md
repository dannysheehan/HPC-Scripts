expirefiles
===========

This script cleans up (removes) user files that have not been accessed for
a configurable number of days.  It also has the option of emailing
users prior to deletion that their files will be deleted and provides a
command line option that allows these users to list their pending files for
deletion for review.
Users also have the option to request exceptions.
The command line tool can also list files that have exceptions.
Exceptions can take the form of user exceptions or path exceptions.
In both cases regular expressions are *not* supported for simplicity.
- *User exceptions* exempt all files for the specified user.
- *Path exceptions* exempt all paths containing the path snipit.
All user messages and exceptions are configurable and contained in a .ini
file under _.expirefiles/config.ini_  in the filesystem that is being
*cleaned up*.
Examples
--------
Create the .expirefiles config files and associated structure under /scratch
~~~
$ sudo expirefiles.py init /scratch
~~~
Find all files under /scratch that are candidates for deletion
~~~
$ sudo expirefiles.py find /scratch
~~~
Notify all users of the pending deletions
~~~
$ sudo expirefiles.py notify /scratch
~~~
A user (in this case userx) lists all files they own scheduled for deletion.
~~~
userx$ expirefiles.py list /scratch
~~~
A user (userx) lists all files they own that are excepted for deletion
~~~
userx$ expirefiles.py list --exception /scratch
~~~
Removes all files under /scratch that are candidates for deletion.
~~~
$ sudo expirefiles.py remove /scratch
~~~
config.ini example
-------------------
- this is the default config.ini file generated when the init option is run.
~~~
[DEFAULT]
last_access_days  = 60
notify_days       = 14
mail_server       = localhost
admin_email       = root
from_email        = admin@widgets.com
from_name         = Support
[exceptions]
user =
   root
path =
   /no-delete/
   /.
[messages]
user_subject =
   IMPORTANT Your {DIR_PATH} files not accessed for %(last_access_days)s days will be deleted on {DELETE_DATE}
user_message =
  Hi {USERNAME},
  .
  This is system generated message.
  ....
  ...
