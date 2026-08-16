goodcitizen.sh
==============

This script is meant to run as a cron job on head nodes every 2 hours.
It sends an email to users using > 80% cpu for more than 1 hour.

It keeps a record of offenders and will only mail them once.


The script assumes you have LDAP based email or similar setup on your head 
nodes that ties email with users userid.

_/etc/postfix/main.cf_
~~~
# Employ canonical mapping to translate address to LDAP aliases as this
# will change both the envelope and the header (hiding cluster internal names)
canonical_maps = ldap:/etc/postfix/ldap-aliases.cf
~~~

You will need to fill this out with your sites LDAP details
_/etc/postfix/ldap-aliases.cf_
~~~
server_host = 
timeout = 5
search_base = 
query_filter = (uid=%s)
result_attribute = mail
version = 3
bind = yes
bind_dn =
bind_pw = 
~~~
