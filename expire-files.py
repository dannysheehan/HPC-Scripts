#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys
import os
import re
import subprocess
import argparse
import traceback
import datetime
import shutil
import smtplib
import pwd

from email.mime.text import MIMEText
from ConfigParser import SafeConfigParser


CONFIG_DIR_NAME      = '.expirefiles'
CONFIG_FILE          = 'config.ini'
CACHE_DIR_NAME       = 'USER_FILE_CACHE'
FILES_TO_DELETE      = 'files_to_delete.raw'

FIND_COMMAND         = '/usr/bin/find' 
LINE_BUFFER          = 1024
MAX_SYSTEM_UID       = 499
  
# for testing
FIND_DEPTH           = 2 


class Config:
  last_access_time     = 3
  admin_email          = 'admin'
  from_email           = 'admin@widgets.com'
  from_name            = 'Support'
  user_msg_template    = ''
  


def find_files(args):
    """ find all files that have not been accessed in Config.last_access_time days
    """
    (config_path, 
     find_path,
     user_exceptions,
     path_exceptions) = initialize_files(args.dirname)

    print "config_path = ", config_path
    print "find_path = ", find_path
    print "user_exceptions = ", user_exceptions
    print "path_exceptions = ", path_exceptions



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

    cmd_args = [FIND_COMMAND, find_path,  
                '-maxdepth', '2', 
                '-atime', '+' + str(Config.last_access_time), 
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
     path_exceptions) = initialize_files(args.dirname)


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


    file_handles = {}
    try:
        for file_name in readlines(files_to_delete_path, LINE_BUFFER):

            if file_name and os.path.exists(file_name):

                userid = os.stat(file_name).st_uid
                user_file_path = os.path.join(user_cache_path, str(userid))

                if userid not in file_handles:
                    file_handles[userid] = open(user_file_path, 'w')

                file_handles[userid].write(file_name + '\0')
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
    files_to_delete = 0

    # check for user exception
    useruid =  os.path.basename(file_list_path)
    if useruid in user_exceptions:
        return 0

    # if there are no exceptions then all files should be deleted.
    if not len(path_exceptions):
        return len(list(readlines(file_list_path)))

    # determine if the filepath is excepted.
    for filename in readlines(file_list_path):
        for path_except in path_exceptions:
            if filename.find(path_except) == -1:
                files_to_delete += 1

    return files_to_delete


def count_files_to_except(file_list_path, user_exceptions, path_exceptions):
    """ Return a count of the number of files excepted from deletion.
    """
    files_to_except = 0

    # check for user exception
    useruid =  os.path.basename(file_list_path)
    if useruid in user_exceptions:
        return len(list(readlines(file_list_path)))

    # Check if there are exceptions.
    if not len(path_exceptions):
        return 0

    # determine if the filepath is excepted.
    for filename in readlines(file_list_path):
        for path_except in path_exceptions:
            if filename.find(path_except) != -1:
                files_to_except += 1

    return files_to_except


def notify_users(args):
    (config_path, 
     find_path,
     user_exceptions,
     path_exceptions) = initialize_files(args.dirname)

    departed_users = []
    system_users = []
    real_users = []
    users_notified = 0

    user_cache_path = os.path.join(config_path, CACHE_DIR_NAME)
    if os.path.exists(user_cache_path):
        print user_cache_path, " exists"
        for file in os.listdir(user_cache_path):
            if file.isdigit():
                user_file_path = os.path.join(user_cache_path, file)
                total_count  = len(list(readlines(user_file_path)))
                user_uid = int(file)

                delete_count = count_files_to_delete(
                            user_file_path,
                            user_exceptions,
                            path_exceptions)

                except_count = count_files_to_except(
                            user_file_path,
                            user_exceptions,
                            path_exceptions)

                print total_count, delete_count, except_count
                assert total_count == delete_count + except_count

                try:
                    username = pwd.getpwuid(user_uid).pw_name
                    if user_uid < MAX_SYSTEM_UID:
                        system_users.append(
                            (username, delete_count, except_count))
                    else:
                        real_users.append(
                            (username, delete_count, except_count))

                except KeyError:
                    departed_users.append(
                            (file, delete_count, except_count))

        admin_msg = overall_usage_msg(real_users, system_users, departed_users)

        if args.check:
            print "-- CHECKING --"
            print admin_msg
        else:
            email_msg(Config.admin_email, admin_msg)
            for (user, delete_count, except_count) in real_users:
                msg = user_usage_msg(user, delete_count, except_count)


def email_msg(user, message):
    """ Mail user a message.
    """
    print "email_msg", user

def overall_usage_msg(real_users, system_users, departed_users):
    """ Generate message for Administrators on usage counts.
    """

    msg = """\
Users with files that have not been accessed in {0} days.

User, Delete File Count, Excepted File Count

Real Users
----------
""".format(Config.last_access_time)

    for user in sorted(real_users, key=lambda tup: tup[1], reverse=True):
        msg += '{0} {1} {2}\n'.format(user[0], user[1], user[2])

    msg += '\nSystem Users\n------------\n'
    for user in sorted(system_users, key=lambda tup: tup[1], reverse=True):
        msg += '{0} {1} {2}\n'.format(user[0], user[1], user[2])

    msg +=  "\nDeparted Users\n--------------\n"
    for user in sorted(departed_users, key=lambda tup: tup[1], reverse=True):
        msg += '{0} {1} {2}\n'.format(user[0], user[1], user[2])

    return msg


def user_usage_msg(user, delete_count, except_count):
    """Generate message specific for user.
    """
    print "email ", user
    print Config.user_msg_template
    print Config.from_name
    print Config.user_msg_template.format(
           USERNAME=user, DELETE_DATE='tbd', COMMAND='tbd')



def remove_files(args):
    (config_path, 
     find_path,
     user_exceptions,
     path_exceptions) = initialize_files(args.dirname)
    """Remove files under 'args.dirname' that have expired and
    have no user or path exceptions.
    """
    pass

def initialize_files(dir_name):
    """Initialize files and directories under 'dir_name'

    Creates required subdirectories and empty config files if they do not 
    already exist, otherwise it will return the existing configuration 
    directory path and existing user and file based exceptions as lists.

    Arguments:
        dir_name: the directory name we are creating configuration files under.
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

    # create expected paths and files if they don't already exist.
    config_path = os.path.join(dir_path, CONFIG_DIR_NAME)
    if not os.path.exists(config_path):
        print "creating ", config_path
        os.mkdir(config_path)

    config_file_path = os.path.join(config_path, CONFIG_FILE)
    if not os.path.exists(config_file_path):
        print "creating ", config_file_path
        with open(os.path.join(config_path, CONFIG_FILE), 'w') as f:
            f.write(
"""
[DEFAULT]
last_access_time  = 3
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
user =
  .Hi {USERNAME},
  . 
  .This is system generated message.
  . 
  .You have files that have not been accessed for over %(last_access_time)s days
  . 
  .These files will be deleted on {DELETE_DATE}.
  .
  .For a list of your files that will be deleted type the following
  .command on a login node.
  . 
  .   {COMMAND}
  .  
  .If you would like to keep these files, you may request an exception
  .from the scheduled deletion by writing to %(from_email)s.
  . 
  .Please note that your exception will *ONLY* be effective for the
  .currently scheduled deletion and you may *NOT* request an exception
  .if you have already had one in place for the previous two deletion
  .cycles.
  . 
  .*If* you have received confirmation of your exception, you may see
  .the list of files that have been excepted by entering the
  .following command on a login node.
  .  
  .  {COMMAND} --exceptions 
  . 
  .    And in this case, no option should now return an empty list.
  . 
  .  Regards
  .  %(from_name)s 
  .  %(from_email)s 
"""
           )

    # load configuration
    parser = SafeConfigParser()
    parser.read(config_file_path)
   
    Config.last_access_time = parser.get('messages', 'last_access_time')
    Config.from_email = parser.get('messages', 'from_email')
    Config.from_name = parser.get('messages', 'from_name')
    Config.user_msg_template = parser.get('messages', 'user')


    # load "user exceptions" 
    for e in parser.get('exceptions', 'user').split('\n'):
        e = e.strip()
        if e != '' and not e.startswith('#'):
            try:
                userid = str(pwd.getpwnam(e).pw_uid)
                print "excepting", userid, e
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
    print "list_files(", args.user, args.exceptions


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
            '--exceptions', help='list exceptions', action='store_true')
    list_parser.set_defaults(func=list_files)

    if real_user != 'root':
        list_parser.add_argument(
            '--user', help='specify user', action='store', default=real_user)
    else:

        list_parser.add_argument(
            '--user', help='specify user', action='store')

        find_parser = subparsers.add_parser('find', help='find files')
        find_parser.add_argument(
                'dirname', action='store', help='Directory ')
        find_parser.set_defaults(func=find_files)
    
        create_parser = subparsers.add_parser(
                'create', help='create user files')
        create_parser.add_argument(
                'dirname', action='store', help='Directory ')
    
        notify_parser = subparsers.add_parser(
                'notify', help='notify users')
        notify_parser.add_argument(
                'dirname', action='store', help='Directory ')
        notify_parser.add_argument(
                '--check', help='check mode', action="store_true")
        notify_parser.set_defaults(func=notify_users)
    
        remove_parser = subparsers.add_parser(
                'remove', help='remove files')
        remove_parser.add_argument(
                'dirname', action='store', help='Directory ')
        remove_parser.set_defaults(func=remove_files)
    
    args = parser.parse_args()
    args.func(args)

    return

        
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
        traceback.print_exc()
        sys.exit(1)
