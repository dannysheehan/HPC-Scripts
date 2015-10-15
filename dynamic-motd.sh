# goes in /etc/profile.d

# show only in interactive sessions
[ -z "$PS1" ] && return

# don't show in screen and tmux
[ "$TERM" = "screen" ] && return

# show only on login nodes
HOSTN=$(/bin/uname -n)
[ "$HOSTN" == "${HOSTN#flashlite}" ] && return

# don't show to system/admin users
ID=$(/usr/bin/id -u)
[ -n "$ID" -a "$ID" -le 2000 ] && return

echo
echo "quotas are implemented for filesystems on flashlite"
echo "  type /usr/local/bin/rquota to see your usage/limits"
echo
/usr/local/bin/rquota
