#!/usr/bin/env python
# -*- coding: utf-8 -*-

""" This script cleans up (removes) user files that have not been accessed for
    a configurable number of days.  It also has the option of emailing
    users prior to deletion that their files will be deleted and provides a
    command line option that allows these users to review their pending files for
    deletion.

    Users also have the option to request exceptions to be put in place.
    The command line tool can also list all files that have exceptions.

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

    A user (in this case userx) lists all files they own that are scheduled for deletion.
    ~~~
    userx$ expirefiles.py list /scratch
    ~~~

    A user (userx) lists all files they own that are excepted from deletion
    ~~~
    userx$ expirefiles.py list --exception /scratch
    ~~~

    Remove all files under /scratch that are candidates for deletion.
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
    ~~~

"""
__author__ = 'Danny Sheehan'
__license__ = "GPL"
__version__ = "1.0.1"
#==============================================================================

import sys
import os
import grp
import re
import subprocess
import argparse
import traceback
import datetime
import shutil
import smtplib
import pwd
import time

from email.mime.text import MIMEText
from ConfigParser import SafeConfigParser


CONFIG_DIR_NAME      = '.expirefiles'
CONFIG_FILE          = 'config.ini'
CACHE_DIR_NAME       = 'USER_FILE_CACHE'
FILES_TO_DELETE      = 'files_to_delete.raw'
FILES_DELETED        = 'files_deleted.txt'

SUPPORT_GROUP        = 'support'

FIND_COMMAND         = '/usr/bin/find' 
LS_COMMAND           = '/bin/ls'

LINE_BUFFER          = 1024

# accounts are considered as system accounts below this UID on most
# UNIX based systems.
MAX_SYSTEM_UID       = 499

# time to sleep between sending individual emails to prevent
# any mail relay from blacklisting us.
MAIL_DELAY_SECS      = 10 
  
# for testing
FIND_DEPTH           = 2 



class Config:
  last_access_days      = 60
  notify_days           = 14
  admin_email           = 'root'
  mail_server           = 'localhost'
  from_email            = 'admin@widgets.com'
  from_name             = 'Support'
  user_subject_template = ''
  user_message_template = ''
  

def find_files(args):
    """ find all files that have not been accessed in 
    Config.last_access_days days
    """
    (config_path, 
     find_path,
     user_exceptions,
     path_exceptions) = load_configuration(args.dirname)

    #print "config_path = ", config_path
    #print "find_path = ", find_path
    #print "user_exceptions = ", user_exceptions
    #print "path_exceptions = ", path_exceptions

    files_to_delete_path  = os.path.join(config_path, FILES_TO_DELETE)

    # make a backup of the previous list of files to delete.
    backup_file_path = \
      files_to_delete_path + '.' + datetime.datetime.now().strftime('%Y%m%d')

    print "make backup of ", files_to_delete_path
    if os.path.exists(files_to_delete_path):
        # remove backup file if it exists.
        if os.path.exists(backup_file_path):
            os.remove(backup_file_path)
        os.rename(files_to_delete_path, backup_file_path)

    # '-maxdepth', '2', 
    cmd_args = [FIND_COMMAND, find_path,  
                '-atime', '+' + str(Config.last_access_days), 
                '-type', 'f', 
                '-fprint0', files_to_delete_path]

    print "Running ", cmd_args
    error_code = subprocess.call(cmd_args)
    if error_code:
        sys.stderr.write('ERROR: no files found\n')
        sys.exit(1)

    create_user_files(args)


def create_user_files(args):
    """ create a file for each user containing a list of files to be deleted.
    """

    (config_path, 
     find_path,
     user_exceptions,
     path_exceptions) = load_configuration(args.dirname)


    files_to_delete_path  = os.path.join(config_path, FILES_TO_DELETE)
    if not os.path.exists(files_to_delete_path):
        sys.stderr.write('ERROR: You must run find first.\n')
        sys.exit(1)

    # remove old cache and create a new one.
    user_cache_path = os.path.join(config_path, CACHE_DIR_NAME)
    if os.path.exists(user_cache_path):
        print "removing tree and contents ", user_cache_path
        shutil.rmtree(user_cache_path)
    print "creating ", user_cache_path
    os.mkdir(user_cache_path)

    path_prefix = ''
    if args.prefix:
        path_prefix =  args.prefix
        print "path prefix =", path_prefix

    file_handles = {}
    try:
        for file_name in readlines(files_to_delete_path, LINE_BUFFER):

            if file_name and os.path.exists(file_name):

                userid = os.stat(file_name).st_uid
                user_file_path = os.path.join(user_cache_path, str(userid))

                if userid not in file_handles:
                    file_handles[userid] = open(user_file_path, 'w')

                file_path = file_name
                if path_prefix:
                    file_path = path_prefix + file_name
                file_handles[userid].write(file_path + '\0')
    finally:
        for file_handle in file_handles.values():
            file_handle.close()


def readlines(filename, bufsize=1024, line_terminator='\0'):
    """ Read terminated lines  from filename.
    Default is null terminated lines.
    """
    buf = ''
    with open(filename, 'r') as f:
        data = f.read(bufsize)
        while data:
            buf += data
            lines = buf.split(line_terminator)
            buf = lines.pop()
            for line in lines: yield line
            data = f.read(bufsize)


def count_files_to_delete(file_list_path, user_exceptions, path_exceptions):
    """ Return a count of the number of files to delete based on exceptions.
    """
    return len(list(list_user_files_to_delete(
                 file_list_path, user_exceptions, path_exceptions)))

def list_all_files_to_delete(file_list_dir, user_exceptions, path_exceptions):
    """ Return a count of the number of files to delete based on exceptions.
    """
    for file in os.listdir(file_list_dir):
        if not file.isdigit(): continue

        user_file_path = os.path.join(file_list_dir, file)
        for filename in list_user_files_to_delete(
                user_file_path,
                user_exceptions,
                path_exceptions): yield filename

def list_user_files_to_delete(file_list_path, user_exceptions, path_exceptions):
    """ Return a count of the number of files to delete based on exceptions.
    """
    #print "list_user_files_to_delete", file_list_path

    # check for user exception
    useruid =  os.path.basename(file_list_path)
    if int(useruid) in user_exceptions:
       return
    else:
        # determine if the filepath is excepted.
        for filename in readlines(file_list_path):
            is_exception = [e for e in path_exceptions 
                                if filename.find(e) != -1 ]
            if not is_exception:
                yield filename


def count_files_to_except(file_list_path, user_exceptions, path_exceptions):
    """ Return a count of the number of files to except based on exceptions.
    """
    return len(list(list_user_files_to_except(
                 file_list_path, user_exceptions, path_exceptions)))

def list_all_files_to_except(file_list_dir, user_exceptions, path_exceptions):
    """ Return a count of the number of files to except based on exceptions.
    """
    for file in os.listdir(file_list_dir):
        if not file.isdigit(): continue

        user_file_path = os.path.join(file_list_dir, file)
        for filename in list_user_files_to_except(
                user_file_path,
                user_exceptions,
                path_exceptions): yield filename


def list_user_files_to_except(file_list_path, user_exceptions, path_exceptions):
    """ Return a count of the number of files excepted from deletion.
    """

    #print "list_user_files_to_except", file_list_path

    # check for user exception
    useruid =  os.path.basename(file_list_path)

    if int(useruid) in user_exceptions:
        for filename in readlines(file_list_path):
            yield filename
    else:
        # determine if the filepath is excepted.
        for filename in readlines(file_list_path):
            is_exception = [e for e in path_exceptions 
                               if filename.find(e) != -1 ]
            if is_exception:
                yield filename

def append_user_file_counts(
        file_counts_list, file_list_path, user_exceptions, path_exceptions):
    """Append user file counts to file_counts list
    """

    exception_count = 0
    total_count = 0
    deletion_count = 0
    user_type = ''

    # path exceptions
    user_name = os.path.basename(file_list_path)

    assert user_name.isdigit()
    user_uid  = int(user_name)

    try:
        user_name = pwd.getpwuid(user_uid).pw_name
        if user_uid < MAX_SYSTEM_UID:
            user_type = 'SYSTEM'
        else:
            user_type = 'REAL'
    except KeyError:
        user_type = 'DEPARTED'

    for filename in readlines(file_list_path):
        total_count += 1
        if user_uid in user_exceptions:
            exception_count += 1
        else:
            is_exception = [e for e in path_exceptions 
                               if filename.find(e) != -1 ]
            if is_exception:
                exception_count += 1
            else:
                deletion_count += 1

    # print user_uid, total_count, deletion_count, exception_count
    assert total_count == exception_count + deletion_count

    file_counts_list.append(
        (user_name, user_type, total_count, deletion_count, exception_count))


def check_user_exists(username):
    """check if the specified user exists and returns uid if user does.
    """

    try:
        user_uid = str(pwd.getpwnam(username).pw_uid)
    except KeyError:
        return None

    return user_uid


def calculate_deletion_date(filepath):
    """ based on the date the find was last run returns the 
    deletion date
    """
    if not os.path.exists(filepath):
        print("There are no files to delete. No find has been run.")
        sys.exit(0)
    else:
        deletion_date = datetime.datetime.fromtimestamp(
            os.path.getmtime(filepath)) + \
            datetime.timedelta(days=Config.notify_days)
        return deletion_date


def notify_users(args):
    """ Notify user/s that they have files that will be deleted.
    """

    (config_path, 
     find_path,
     user_exceptions,
     path_exceptions) = load_configuration(args.dirname)

    file_counts_list = []


    files_to_delete_path  = os.path.join(config_path, FILES_TO_DELETE)
    if not os.path.exists(files_to_delete_path):
        sys.stderr.write('ERROR: You must run find first.\n')
        sys.exit(1)

    user_cache_path = os.path.join(config_path, CACHE_DIR_NAME)
    assert os.path.exists(user_cache_path)

    deletion_date = calculate_deletion_date(files_to_delete_path)
    deletion_datestr =  deletion_date.strftime('%a %d %B %Y')

    now_time = datetime.datetime.now()
    if now_time > deletion_date:
        print(
          'Scheduled deletion would have occurred on {0}'.
          format(deletion_datestr))
        sys.exit(0)


    # Notify one user
    if args.user:
        user_uid = check_user_exists(args.user)
        if user_uid == None:
            sys.stderr.write(
                'ERROR: invalid username -> ' + args.user + '\n' )
            sys.exit(1)

        user_file_path = os.path.join(user_cache_path, user_uid)
        if not os.path.exists(user_file_path):
            print("User {0} has no files to delete".format(args.user))
            sys.exit(0)

        append_user_file_counts(
            file_counts_list,
            user_file_path,
            user_exceptions,
            path_exceptions)

    # Notify all users
    else:
        for file in os.listdir(user_cache_path):

            if not file.isdigit(): continue

            user_file_path = os.path.join(user_cache_path, file)
            append_user_file_counts(
                file_counts_list,
                user_file_path,
                user_exceptions,
                path_exceptions)


    admin_msg = overall_usage_message(file_counts_list, deletion_datestr)
    
    if args.check:
        print "-- CHECKING --"
        print admin_msg
    else:
        subject = "{0} files cleanup scheduled for {1}".format(
                args.dirname,  deletion_datestr)
            
        email_msg(Config.admin_email, subject, admin_msg)
        for user in file_counts_list:
            # only notify real users.
            if user[1] == 'REAL':
                time.sleep(MAIL_DELAY_SECS)
                user_command = __file__ + ' list ' + find_path

                subject = \
                    "IMPORTANT Your {0} files cleanup scheduled for {1}".format(
                            args.dirname,  deletion_datestr)

                subject = user_usage_subject(deletion_datestr, find_path)

                message = user_usage_message(
                      user, deletion_datestr, user_command, find_path)
                email_msg(user[0], subject, message)


def email_msg(user, subject, message):
    """ Mail user a message with given subject.
    """

    msg = MIMEText(message)

    msg['To'] = user
    msg['From'] = Config.from_email
    msg['subject'] = subject
    server = smtplib.SMTP(Config.mail_server)
    try:
        server.sendmail(
                Config.from_email,
                [user],
                msg.as_string())
    finally:
        server.quit()


def overall_usage_message(file_counts_list, deletion_datestr):
    """ Generate message for Administrators on usage counts.
    """

    msg = """
Deletion is scheduled to occur on {1}.

Counts of files that have not been accessed in {0} days.

User, TotalFileCount DeleteFileCount ExceptedFileCount

Real Users
----------
""".format(Config.last_access_days, deletion_datestr)

    real_users = [ u for u in file_counts_list if u[1] == 'REAL' ]
    for user in sorted(real_users, key=lambda tup: tup[2], reverse=True):
        msg += '{0} {1} {2} {3}\n'.format(user[0], user[2], user[3], user[4])

    msg += '\nSystem Users\n------------\n'
    system_users = [ u for u in file_counts_list if u[1] == 'SYSTEM' ]
    for user in sorted(system_users, key=lambda tup: tup[2], reverse=True):
        msg += '{0} {1} {2} {3}\n'.format(user[0], user[2], user[3], user[4])

    msg +=  "\nDeparted Users\n--------------\n"
    departed_users = [ u for u in file_counts_list if u[1] == 'DEPARTED' ]
    for user in sorted(departed_users, key=lambda tup: tup[2], reverse=True):
        msg += '{0} {1} {2} {3}\n'.format(user[0], user[2], user[3], user[4])

    return msg


def user_usage_subject(deletion_datestr, dir_path):
    """Generate subject specific for user message
       Example:  IMPORTANT Your {DIR_PATH} files not accessed for %(last_access_days)s days will be deleted on {DELETE_DATE}
    """

    return Config.user_subject_template.format(
           DELETE_DATE=deletion_datestr,
           DIR_PATH=dir_path)


def user_usage_message(user, deletion_datestr, user_command, dir_path):
    """Generate message specific for user.
    """

    user_name = user[0]
    user_gecos = pwd.getpwnam(user_name).pw_gecos
    
    return Config.user_message_template.format(
           USERNAME=user_gecos,
           DELETE_DATE=deletion_datestr,
           DIR_PATH=dir_path,
           COMMAND=user_command)


def remove_file(filename, check=False):
    """Removes specified file but only if it exists
    and the access time is greater than the Configured max access time.
    Just print filname if in check mode
    """

    now_time = time.time()

    if os.path.exists(filename):
        # recheck access time of file.
        last_access_days =  (now_time - os.path.getatime(filename)) / 24 / 3600 
        if last_access_days > Config.last_access_days:
            if check:
                # print last access time listing of file to be deleted.
                cmd_args = [LS_COMMAND, '-lud', filename]
                check = subprocess.check_output(cmd_args)
                print check
                return ''

            else:
                try:
                    cmd_args = [LS_COMMAND, '-lud', filename]
                    check = subprocess.check_output(cmd_args)

                    os.remove(filename)
                    return check

                except OSError, e:
                    sys.stderr.write(
                        'ERROR: {0} - {1}\n'.format(e.filename, e.strerror))
                    sys.exit(1)


def remove_files(args):
    """Remove files under 'args.dirname' that have expired and
    have no user or path exceptions.
    """

    (config_path, 
     find_path,
     user_exceptions,
     path_exceptions) = load_configuration(args.dirname)

    #print "config_path = ", config_path
    #print "find_path = ", find_path
    #print "user_exceptions = ", user_exceptions
    #print "path_exceptions = ", path_exceptions

    files_deleted_path  = os.path.join(config_path, FILES_DELETED)

    # make a backup of the previous files deleted list
    backup_file_path = \
      files_deleted_path + '.' + datetime.datetime.now().strftime('%Y%m%d')

    print "make backup of ", files_deleted_path
    if os.path.exists(files_deleted_path):
        # remove backup file if it exists.
        if os.path.exists(backup_file_path):
            os.remove(backup_file_path)
        os.rename(files_deleted_path, backup_file_path)


    user_cache_path = os.path.join(config_path, CACHE_DIR_NAME)
    assert os.path.exists(user_cache_path)

    # remove files for all users. 
    if not args.user:

        # keep an audit of deleted files.
        with open(files_deleted_path, 'w') as f:
            for filename in list_all_files_to_delete(
                    user_cache_path,
                    user_exceptions,
                    path_exceptions):
                deleted = remove_file(filename, args.check)
                # keep audit of deleted file name and last access time of that file.
                if deleted: f.write(deleted)

    # or, for specific user (NOTE: no audit of deleted files is kept in this case).
    else:
        user_uid = check_user_exists(args.user)
        if user_uid == None:
            sys.stderr.write(
                'ERROR: invalid username -> ' + args.user + '\n' )
            sys.exit(1)

        user_file_path = os.path.join(user_cache_path, user_uid)
        for filename in list_user_files_to_delete(
                user_file_path,
                user_exceptions,
                path_exceptions): 
            deleted = remove_file(filename, args.check)



def output_crontab(dir_path):
    """Output crontab options based on file deletion list creation date
    and the configuration settings for delete interval.
    If there is no file deletion list then just pick the first day of the
    month for the file deletion list creation date (the "find").
    """

    config_path = os.path.join(dir_path, CONFIG_DIR_NAME)
    files_to_delete_path  = os.path.join(config_path, FILES_TO_DELETE)

    # if find has not been run, then just pick first day of month to
    # run cronjobs.
    if not os.path.exists(files_to_delete_path):
        find_day = 1
        deletion_day = find_day + Config.notify_days
    else:
        # Calculate deletion date based on timestame of file delete list.
        find_date =  datetime.datetime.fromtimestamp(
            os.path.getmtime(files_to_delete_path))
        find_day =  find_date.strftime('%d')

        deletion_date = calculate_deletion_date(files_to_delete_path)
        deletion_datestr =  deletion_date.strftime('%a %d %B %Y')
        deletion_day =  int(deletion_date.strftime('%d'))

        print("deletion should be scheduled for {0}".format(deletion_datestr))

    # send warning one day after files to delete list is generated.
    send_warning_day = int(find_day) + 1

    # cater for shortest month
    if send_warning_day > 28:
       send_warning_day = 1

    if deletion_day > 28:
        deletion_day = 1

    # arbitrary cron min and hour values.
    cron_min = 11 
    cron_hour = 2

    print('\nexample crontab entries based on configuration & last find run\n')
    print('{0} {1} {2} * * {3} find {4}'.format(
              cron_min, cron_hour, find_day, __file__, dir_path))
    print('{0} {1} {2} * * {3} notify {4}'.format(
              cron_min, cron_hour, send_warning_day, __file__, dir_path))
    print('{0} {1} {2} * * {3} delete {4}'.format(
              cron_min, cron_hour, deletion_day, __file__, dir_path))


def init_files(args):
    """Initialize files and directories under 'dir_name'

    Creates required subdirectories and empty config files if they do not 
    already exist, otherwise it will return the existing configuration 
    directory path and existing user and file based exceptions as lists.

    Arguments:
        dir_name: the directory name we are creating configuration files under.
    """

    dir_name = args.dirname

    config_path = ''
    user_exceptions = []
    path_exceptions = []

    # get full path 
    dir_path = os.path.abspath(dir_name)
    if not os.path.exists(dir_path):
        print "path %s does not exist" % dir_path
        sys.exit(1)

    if os.path.islink(dir_path):
        print "path %s is symlink" % dir_path
        sys.exit(1)

    # create expected paths and files if they don't already exist.
    config_path = os.path.join(dir_path, CONFIG_DIR_NAME)
    if not os.path.exists(config_path):
        print "creating ", config_path
        os.mkdir(config_path)

    config_file_path = os.path.join(config_path, CONFIG_FILE)
    if os.path.exists(config_file_path):
        (config_path, 
         find_path,
         user_exceptions,
         path_exceptions) = load_configuration(dir_name)
        print "%s already exists " % config_file_path
        output_crontab(dir_path)
        sys.exit(0)
    else:
        print "creating ", config_file_path
        with open(os.path.join(config_path, CONFIG_FILE), 'w') as f:
            f.write(
"""
[DEFAULT]
last_access_days  = 60
notify_days       = 14 
mail_server       = localhost
admin_email       = admin
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
  . 
  You have files that have not been accessed for over %(last_access_days)s days
  under {DIR_PATH}.
  .
  These files will be deleted on {DELETE_DATE}.
  . 
  For a list of your files that will be deleted type the following
  command on a login node.
  . 
  .   {COMMAND}
  .  
  If you would like to keep these files, you may request an exception
  from the scheduled deletion by writing to %(from_email)s.
  . 
  Please note that your exception will *ONLY* be effective for the
  currently scheduled deletion and you may *NOT* request an exception
  if you have already had one in place for the previous two deletion
  cycles.
  . 
  *If* you have received confirmation of your exception, you may see
  the list of files that have been excepted by entering the
  following command on a login node.
  .  
  .  {COMMAND}  --exceptions 
  . 
  .    And in this case, no option should now return an empty list.
  . 
  Regards
  %(from_name)s 
  %(from_email)s 
"""
           )

def load_configuration(dir_name):
    """load configuration associated with specified diectory
    """
    config_path = ''
    user_exceptions = []
    path_exceptions = []

    # get full path 
    dir_path = os.path.abspath(dir_name)
    if not os.path.exists(dir_path):
        print "path %s does not exist" % dir_path
        sys.exit(1)

    if os.path.islink(dir_path):
        print "path %s is symlink" % dir_path
        sys.exit(1)

    config_path = os.path.join(dir_path, CONFIG_DIR_NAME)
    config_file_path = os.path.join(config_path, CONFIG_FILE)
    if not os.path.exists(config_file_path):
        print "no configuration found for %s. Please run 'init' first." % dir_path
        sys.exit(1)

    # load configuration
    parser = SafeConfigParser()
    parser.read(config_file_path)
  
    # TBD  -  configuration checks needed - sanity checks.
    Config.last_access_days = int(parser.get(
                                       'messages', 'last_access_days'))
    Config.notify_days = int(parser.get('messages', 'notify_days'))

    # Give users at least 7 days notice for deletion but no more than 28.
    # also makes for easier contab configuration.
    if Config.notify_days > 28 or Config.notify_days < 7:
        sys.stderr.write(
            'CONFIG_ERROR: notify_days needs to be <= 28 days and >= 7 days\n')
        sys.exit(1)

    Config.mail_server = parser.get('messages', 'mail_server')
    Config.admin_email = parser.get('messages', 'admin_email')

    Config.from_email = parser.get('messages', 'from_email')
    Config.from_name = parser.get('messages', 'from_name')

    Config.user_message_template = parser.get('messages', 'user_message')
    Config.user_subject_template = parser.get('messages', 'user_subject')

    # load "user exceptions" 
    for e in parser.get('exceptions', 'user').split('\n'):

        e = e.strip()
        if e == '' or e.startswith('#'):
            continue

        if e.isdigit():
            user_exceptions.append(int(e))
        else:
            try:
                userid = pwd.getpwnam(e).pw_uid
                user_exceptions.append(userid)
            except KeyError:
                sys.stderr.write(
                    'ERROR: invalid username in user exceptions file -> ' + \
                    e + '\n' )
                sys.exit(2)

    # load "path exceptions"
    for e in parser.get('exceptions', 'path').split('\n'):
        e = e.strip()
        if e != '' and not e.startswith('#'):
            path_exceptions.append(e)

    return (config_path, dir_path, user_exceptions, path_exceptions)


def list_files(args):
    """ list the files sheduled for deletion or excepted from deletion
    for all users or the specified user.
    """

    (config_path, 
     find_path,
     user_exceptions,
     path_exceptions) = load_configuration(args.dirname)

    #print "config_path = ", config_path
    #print "find_path = ", find_path
    #print "user_exceptions = ", user_exceptions
    #print "path_exceptions = ", path_exceptions

    #print "list_files(", args.user, args.exceptions

    user_cache_path = os.path.join(config_path, CACHE_DIR_NAME)
    assert os.path.exists(user_cache_path)

    files_to_delete_path = os.path.join(config_path, FILES_TO_DELETE)
    deletion_date = calculate_deletion_date(files_to_delete_path)
    deletion_datestr =  deletion_date.strftime('%a %d %B %Y')

    now_time = datetime.datetime.now()
    if now_time > deletion_date:
        sys.stderr.write(
          'Scheduled deletion would have already occurred on ' + \
          format(deletion_datestr) + '\n')
        sys.exit(0)

    if args.check:
        print('Scheduled deletion should occur around {0}'.
                format(deletion_datestr))
        sys.exit(0)
        


    if args.user == None:
        if args.exceptions:
            for file in list_all_files_to_except(
                    user_cache_path, user_exceptions, path_exceptions):
                print file
        else:
            for file in list_all_files_to_delete(
                    user_cache_path, user_exceptions, path_exceptions):
                print file

    else:
        user_uid = check_user_exists(args.user)
        if user_uid == None:
            if args.user.isdigit():
                user_uid = args.user
            else:
                sys.stderr.write(
                    'ERROR: invalid username -> ' + args.user + '\n' )
                sys.exit(1)


        user_file_path = os.path.join(user_cache_path, user_uid)
        if not os.path.exists(user_file_path):
            print("User {0} has no files to delete".format(args.user))
            sys.exit(0)

        if args.exceptions:
            for file in list_user_files_to_except(
                    user_file_path, user_exceptions, path_exceptions):
                print file
        else:
            for file in list_user_files_to_delete(
                    user_file_path, user_exceptions, path_exceptions):
                print file

def is_group_member(group_name):
    """ Returns true if the current user is a member of group_name
    """

    try:
        user_groups = os.getgroups()
        guid = grp.getgrnam(group_name).gr_gid

        print group_name, guid, user_groups
        return guid in user_groups

    except KeyError:
        return False


def main():
    #
    # The command options are different depending on if the user is
    # root or not.
    #
    # http://pymotw.com/2/pwd/
    real_user = pwd.getpwuid(os.getuid()).pw_name
    
    parser = argparse.ArgumentParser(description='Expires files!')
    subparsers = parser.add_subparsers(help='commands')
    list_parser = subparsers.add_parser(
            'list', help='list files to be deleted')
    list_parser.add_argument(
                'dirname', action='store', help='Directory ')
    list_parser.add_argument(
            '--exceptions', help='list exceptions', action='store_true')
    list_parser.add_argument(
                '--check', help='check mode', action="store_true")
    list_parser.set_defaults(func=list_files)

    if real_user != 'root' and not is_group_member(SUPPORT_GROUP):
        list_parser.add_argument(
            '--user', help='specify user', action='store', default=real_user)
    else:

        list_parser.add_argument(
            '--user', help='specify user', action='store')

        init_parser = subparsers.add_parser('init', help='inialize files')
        init_parser.add_argument(
                'dirname', action='store', help='Directory ')
        init_parser.add_argument(
                '--check', help='check mode', action="store_true")
        init_parser.set_defaults(func=init_files)
    

        find_parser = subparsers.add_parser('find', help='find files')
        find_parser.add_argument(
                'dirname', action='store', help='Directory ')
        find_parser.add_argument(
                '--prefix', help='path prefix', action="store")
        find_parser.set_defaults(func=find_files)
    
        #create_parser = subparsers.add_parser(
        #        'create', help='create user files')
        #create_parser.add_argument(
        #        'dirname', action='store', help='Directory ')
    
        notify_parser = subparsers.add_parser(
                'notify', help='notify users')
        notify_parser.add_argument(
                'dirname', action='store', help='Directory ')
        notify_parser.add_argument(
                '--check', help='check mode', action="store_true")
        notify_parser.add_argument(
            '--user', help='specify user', action='store')
        notify_parser.set_defaults(func=notify_users)
    
        remove_parser = subparsers.add_parser(
                'remove', help='remove files')
        remove_parser.add_argument(
            '--user', help='specify user', action='store')
        remove_parser.add_argument(
                '--check', help='check mode', action="store_true")
        remove_parser.add_argument(
                'dirname', action='store', help='Directory ')
        remove_parser.set_defaults(func=remove_files)
    
    args = parser.parse_args()
    args.func(args)

    return

if sys.version_info<(2,7,0):
    sys.stderr.write("You need python 2.7 or later to run this script\n")
    sys.exit(1)

        
if __name__ == '__main__':
    try:
        main()
        sys.exit(0)
    except KeyboardInterrupt, e:
        raise e
    except SystemExit, e:
        raise e
    except Exception, e:
        print str(e)
        # traceback.print_exc()
        sys.exit(1)
