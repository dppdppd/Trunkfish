#!/bin/sh

#set -o verbose #echo on
#set +o verbose #echo off

# Server name or IP ( e.g. "drobo-fs.local" )
SERVER="drobo-fs.local"

# Server user that will execute the rsync ( e.g. "root" )
SUSER="root"

# Full path of backup destination directory on the server. ( e.g. "/mnt/DroboFS/Shares/backup/IdosComputer" )
REMOTEDIR="/mnt/DroboFS/Shares/backup/LionO"

ssh ${SUSER}@${SERVER} "find "$REMOTEDIR" -maxdepth 2 -name "_backup.log" -type f | xargs grep -l $1 | xargs ls -let | sort -k 10 -k 7 -k 8 -k 9 | awk '{print \$11}'| xargs grep -h $1 | grep '\ \<'| awk '{printf \"%s\t\",\$1; for (i = 4; i <= NF; i++) {printf \" %s\",\$i}; printf \"\n\" }' | tail -n $2"
