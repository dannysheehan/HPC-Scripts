#!/bin/bash

BDIR=$1


mkdir -p "$BDIR/.du"
DIRTREE="$BDIR/.du/.dir_tree.txt"
DU_OUT="$BDIR/.du/du_new.txt"

touch $DU_OUT

owners()
{
  PPREV="x"
  PREV_U=""
  cat $DIRTREE | while IFS= read -r -d '' d
  do
    CUR=$d
    while [ "${CUR}" != '.' ]
    do
       PREV=$CUR
       CUR=$(dirname "$CUR")
       PREV_U=$(stat -c '%U' "$PREV")
       CUR_U=$(stat -c '%U' "$CUR")
       if [ "$PREV_U" != "$CUR_U" ]
       then
            if ! egrep -q "^${PREV_U},${PREV},[0-9]*$" $DU_OUT
            then
              echo "$PREV_U $PREV" >&2
              DU=$(du -skx "$PREV")
              DU_USAGE=$(echo $DU | awk '{print $1}')
              DU_DIR=$(echo $DU | awk '{print $2}')
              echo "$PREV_U,$DU_DIR,$DU_USAGE" >> $DU_OUT
            fi
       fi
    done

    if [ -n "$PREV_U" ] && ! egrep -q "^${PREV_U},${PREV},[0-9]*$" "$DU_OUT"
    then
      echo "$PREV_U $PREV" >&2
      DU=$(du -skx "$PREV")
      DU_USAGE=$(echo $DU | awk '{print $1}')
      DU_DIR=$(echo $DU | awk '{print $2}')
      echo "$PREV_U,$DU_DIR,$DU_USAGE" >> $DU_OUT
    fi
  
  done
}


DEPTH=3
cd $BDIR
find . \
     -maxdepth $DEPTH -mindepth 1 \
     -type d -print0 \
     > $DIRTREE

owners

