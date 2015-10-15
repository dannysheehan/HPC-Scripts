LOAD=$(uptime | cut -d\, -f3  | awk '{print $3}')
NCPU=$(lscpu | awk -F\: '/^Socket/ {s=$2} /Core/ {c=$2} END { print (c * s) }')

if [ -n "$LOAD" -a -n "$NCPU" ] && [ $(echo "$LOAD > (($NCPU * 2))" | bc) -eq 1 ]
then
   echo  "load $LOAD > cpu $NCPU"
fi    

