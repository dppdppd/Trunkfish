#!/bin/sh

#==============================================================================
#  Copyright 2011 Ido Magal. All rights reserved. 
#
#   DISCLAIMER: USE AT YOUR OWN RISK. YOU ARE RESPONSIBLE FOR READING AND UNDERSTANDING THE CODE
#               IN THIS SCRIPT AND NO GUARANTEE IS GIVEN OR IMPLIED.
#               
#               THIS CODE MAY ERASE EVERYTHING, ANYWHERE, AT ANY MOMENT.
#
#
#   Files that go with this script:\
#
#       trunkfi.sh              -   This file. Does the backing up.
#       trunkfish.cf            -   The configuration file. You should edit this file before you run backup.sh for the first time.
#       find_trunkfi.sh         -   A script to identify when a file was was most recently updated.
#       ~trunkfish_excludes.txt -   A txt file gets created from backup_settings.cfg, and contains rsync filters for the backup.
#       ~trunkfish.log          -   A log of the backup events.
#       ~trunk_err.log          -   A log of backup errors, if there are any.
#
#       TODO:
#           - test ssh setup
#           - add a script that unloads and deletes plist
#           - merge setup scripts into this one
#           - make sure dry run is enforced throughout all scripts
#           - require root for setup scripts
#
#  Email:   M8R-u8t2l4 AT mailinator DOT com
#==============================================================================

# Directory where this script is located.
ScriptDir="$( cd -P "$( dirname "$0" )" && pwd )"

# File names and paths
ScriptPath="$ScriptDir/trunkfi.sh"
SettingsPath="$ScriptDir/trunkfish.cfg"
SSHSetupScriptPath="$ScriptDir/setup_ssh_trunkfi.sh"
SchedSetupScriptPath="$ScriptDir/schedule_trunkfi.sh"
LockPath="$ScriptDir/~trunkfish_lock.pid"
ExcludesPath="$ScriptDir/~trunkfish_excludes.txt"
StdLogPath="$ScriptDir/~trunkfish.log"
ErrLogPath="$ScriptDir/~trunk_err.log"

if [ ! -e "$SettingsPath" ]; then
echo "\t $SettingsPath is missing. Cannot continue."
exit 1
fi

# Load settings
. "$SettingsPath"

# Today
Today=$(date +$DateFormat)

for var in "$@"; do
    case "$var" in

        --dryrun)       DRYRUN="echo DRY RUN: -- "; NOLOGS=1;;

        --nologs)       NOLOGS=1;;

        --setup-ssh)    . $SSHSetupScriptPath; exit 0;;

        --schedule)     . $SchedSetupScriptPath; exit 0;;

        --unschedule)   . $SchedSetupScriptPath; exit 0;;

        --new)          NEWBACKUP=1;;

        *) 
            echo
            echo "Valid options:"
            echo
            echo "--setup-SSH   Set up password-less SSH for automated backup."
            echo "--schedule    Specify the hour of day to backup, where '0' is Midnight and '13' is 1pm."
            echo "--unschedule  Disable the daily scheduled backup."
            echo "--new         Use this the first time you back up to skip searching for a previous backup to link to."
            echo "--dryrun      Use this to confirm the script is set up correctly. Nothing will actually execute."
            echo
            exit 1;;
    esac
done

# copy filters from Settings into an exclude file for rsync.
echo "$RsyncFilter" > $ExcludesPath

# number of days to search back for a backup to link to before giving up.
SearchDays=30

# Full backup path ( dir/date )
RemotePath=$RemoteDir"/"$Today

# Temp variable for searching previous backup
_days=1

# Last backup
PrevDate=$(date -v -${_days}d +"$DateFormat")

# If backup fails, delete partial backup and clean up.
function trap_backup() {
    trap - ERR
    echo "\t $(TimeStamp) Backup aborted. Cleaning up and deleting lock..."
    $DRYRUN ssh ${ServerUser}@${Server} "mv ${RemotePath}.incomplete ${RemotePath}.aborted.$$" &>/dev/null
    $DRYRUN ssh ${ServerUser}@${Server} "nohup rm -r -f ${RemotePath}.aborted.$$ &" &>/dev/null

    # save the logs of the failed backup  
    $DRYRUN mv $StdLogPath $ScriptDir"/"BACKUP_FAILED."${Today}".log &>/dev/null
    $DRYRUN mv $StdErr $ScriptDir"/"BACKUP_ERR_FAILED."${Today}".log &>/dev/null
    $DRYRUN rm "$LockPath" &>/dev/null
    exit 1
}

# Validate directories
if [ ! -e "$BackupDir" ]; then
echo "\t $(TimeStamp) The directory you are attempting to back up, \"$BackupDir\", does not exist."
exit 1
fi
if [ 0 -ne `ssh ${ServerUser}@${Server} test -d "$RemoteDir" ;echo \$?` ]; then
    echo "\t $(TimeStamp) $RemoteDir does not exist. If you're backing up to a DroboFS, use the Dashboard to create the Share."
    exit 1
fi
if [ 0 -ne `ssh ${ServerUser}@${Server} test -f "$RsyncPath" ;echo \$?` ]; then
    echo "\t $(TimeStamp) $RsyncPath does not exist. You either haven't installed rsync or you have the wrong path to it in the \$RsyncPath variable in this script."
    exit 1
fi
if [ ! -e "$ExcludesPath" ]; then
    echo "\t $(TimeStamp) $ExcludesPath does not exist. Rsync will not exclude any files."
    ExcludesPath=""
fi

#========================================================
# Stuff starts happening here.
#========================================================

if [ -z "$DRYRUN" ]; then

    # Abort if the LockPath exists
    if [ -e $LockPath ]; then
        echo "\t $(TimeStamp) Lock file exists, which means the previous backup did not end gracefully. Delete $LockPath and retry."
        exit 1
    fi

    # Start by deleting the old logs
    rm -f "$StdLogPath" &>/dev/null
    rm -f "$ErrLogPath" &>/dev/null

    # Capture outputs in new log files

    if [ -z "$NOLOGS" ]; then
        exec > "$StdLogPath" 2>"$ErrLogPath"
    fi

    # Create a LockPath with the PID to prevent the script running more than once a time.
    echo "$$" >"$LockPath"

fi
echo
echo
echo "\t $(TimeStamp) Starting..."

#========================================================
# Find the previous backup, to which we're going to link against. 
#========================================================

if [ -z $NEWBACKUP ]; then echo "\t $(TimeStamp) Searching for the most recent backup, to which we're going to link today's backup..."; fi

# Check if there already exists a backup for today. If so, move it to ".incomplete" and backup into it, picking up whatever has changed since.
if [ 0 -eq `ssh ${ServerUser}@${Server} test -d "$RemoteDir"/"$Today".d ;echo \$?` ]; then
    echo "\t $(TimeStamp) There already exists a backup for today: ${Today}. I will update it."
    $DRYRUN ssh ${ServerUser}@${Server} "mv ${RemotePath}.d ${RemotePath}.incomplete"
fi

while [ -z $NEWBACKUP ] && [ 1 -eq `ssh ${ServerUser}@${Server} test -d "$RemoteDir"/"$PrevDate".d ;echo \$?` ]
do
    _days=`expr $_days + 1`
    if [ ${SearchDays} -eq ${_days} ]; then
        echo "I can't find a previous backup less than $SearchDays days old."
        echo "Is this your first backup?"
        echo "Yes: Start a fresh backup with no linking."
        echo "No:  Keep searching for an even older backup."
        select yn in "Yes" "No";
        do
            case $yn in
                Yes ) NEWBACKUP=1; break;;
                No ) SearchDays=`expr $SearchDays + $SearchDays`; echo $SearchDays; break;;
            esac
        done
    fi
    PrevDate=$(date -v -${_days}d +"$DateFormat")
done

if [ -n $NEWBACKUP ]; then
    $PrevDate="NONE"
fi

#========================================================
# Print working variables for debugging and the logs
#========================================================
echo
echo ------------------------------------------------------------------------------
echo "Today's date:  $Today"
echo "Last backup:   $PrevDate";;
echo "Backing up:    $BackupDir"
echo "Destination:   $RemoteDir"
echo "Server user:   $ServerUser"
echo "Server:        $Server"
echo "Output Log:    $StdLogPath"
echo "Error Log:     $ErrLogPath"
echo "Lock File:     $LockPath"
echo "Excludes File: $ExcludesPath"
echo ------------------------------------------------------------------------------
echo
echo "Exclude file contents:"
cat $ExcludesPath
echo ------------------------------------------------------------------------------
echo

#========================================================
# BACKUP happens here.
#========================================================
# Use trap to delete the partial backup if it doesn't complete.
# If we don't delete it, the next backup will generate lots of duplicate files because it will link to this partial directory. We'd rather it link to the previous good backup.

trap trap_backup ERR
$DRYRUN rsync --stats --bwlimit=1000 --force --ignore-errors --delete-excluded --exclude-from="$ExcludesPath" --delete -avz --rsync-path="$RsyncPath" --out-format="%t %i %f%L" -e 'ssh -p 22' --link-dest=../"$PrevDate".d "$BackupDir" ${ServerUser}@${Server}:${RemotePath}.incomplete/
trap - ERR


# backup was successful. Rename it.
echo "\t $(TimeStamp) backup completed successfully. Renaming ${RemotePath}.incomplete to ${RemotePath}.d"
$DRYRUN ssh ${ServerUser}@${Server} "mv ${RemotePath}.incomplete ${RemotePath}.d"

# Backup is done. Copy the logs into the backup dir.
if [ -z $NOLOGS ]; then
    echo "\t $(TimeStamp) Copying the logs..."
    $DRYRUN rsync --rsync-path="$RsyncPath" -e 'ssh -p 22' "$StdLogPath" ${ServerUser}@${Server}:${RemotePath}.d/
    $DRYRUN rsync --rsync-path="$RsyncPath" -e 'ssh -p 22' "$ErrLogPath" ${ServerUser}@${Server}:${RemotePath}.d/
fi

#========================================================
# Save off weekly, monthly, yearly, copies
#========================================================
# If we haven't saved off a backup in a week/month/year, then save one. The trap deletes the partial dir if the copy fails.

function trap_weeklybackup() {
    echo "\t $(TimeStamp) Aborting weekly save..."
    $DRYRUN ssh ${ServerUser}@${Server} "rm -r -f ${RemotePath}.w"
}

function trap_monthlybackup() {
    echo "\t $(TimeStamp) Aborting monthly save..."
    $DRYRUN ssh ${ServerUser}@${Server} "rm -r -f ${RemotePath}.m"
}

function trap_yearlybackup() {
    echo "\t $(TimeStamp) Aborting yearly save..."
    $DRYRUN ssh ${ServerUser}@${Server} "rm -r -f ${RemotePath}.y"
}

if [ 0 -ne $W_Hist ]; then
    echo "\t $(TimeStamp) Checking if it is time to save off a weekly backup..."
    if [ -z `ssh ${ServerUser}@${Server} "find "$RemoteDir" -type d -name "*.w" -maxdepth 1 -mtime -7"` ]; then
        echo "\t $(TimeStamp) Saving off a weekly backup..."
        trap trap_weeklybackup INT TERM EXIT
        $DRYRUN ssh ${ServerUser}@${Server} "cp -al ${RemotePath}.d ${RemotePath}.w"
        trap - INT TERM EXIT
    fi
fi

if [ 0 -ne $M_Hist ]; then
    echo "\t $(TimeStamp) Checking if it is time to save off a monthly backup..."
    if [ -z `ssh ${ServerUser}@${Server} "find "$RemoteDir" -type d -name "*.m" -maxdepth 1 -mtime -30"` ]; then
        echo "\t $(TimeStamp) Saving off a monthly backup..."
        trap trap_monthlybackup INT TERM EXIT
        $DRYRUN ssh ${ServerUser}@${Server} "cp -al ${RemotePath}.d ${RemotePath}.m"
        trap - INT TERM EXIT

    fi
fi

if [ 0 -ne $Y_Hist ]; then
    echo "\t $(TimeStamp) Checking if it is time to save off a yearly backup..."
    if [ -z `ssh ${ServerUser}@${Server} "find "$RemoteDir" -type d -name "*.y" -maxdepth 1 -mtime -365"` ]; then
        echo "\t $(TimeStamp) Saving off a yearly backup..."
        trap trap_yearlybackup INT TERM EXIT
        $DRYRUN ssh ${ServerUser}@${Server} "cp -al ${RemotePath}.d ${RemotePath}.y"
        trap - INT TERM EXIT
    fi
fi

#========================================================
# Clean up old backups
#========================================================

trap "exit 1" ERR
if [ -z $NEWBACKUP ]; then
if [ $D_Hist -gt -1 ]; then 
echo "\t $(TimeStamp) Searching for daily backups older than $D_Hist days to delete..."
ssh ${ServerUser}@${Server} "find "$RemoteDir" -maxdepth 1 -type d -name \"*.d\" -mtime +$D_Hist -print0 | xargs -0 -r $DRYRUN rm -r -f"
fi
if [ $W_Hist -gt -1 ]; then
echo "\t $(TimeStamp) Searching for weekly backups older than $W_Hist weeks to delete..."
ssh ${ServerUser}@${Server} "find "$RemoteDir" -maxdepth 1 -type d -name \"*.w\" -mtime +`expr $W_Hist \* 7` -print0 | xargs -0 -r $DRYRUN rm -r -f"
fi
if [ $M_Hist -gt -1 ]; then
echo "\t $(TimeStamp) Searching for monthly backups older than $M_Hist weeks to delete..."
ssh ${ServerUser}@${Server} "find "$RemoteDir" -maxdepth 1 -type d -name \"*.m\" -mtime +`expr $M_Hist \* 30` -print0 | xargs -0 -r $DRYRUN rm -r -f"
fi
if [ $Y_Hist -gt -1 ]; then
echo "\t $(TimeStamp) Searching for yearly backups older than $Y_Hist years to delete..."
ssh ${ServerUser}@${Server} "find "$RemoteDir" -maxdepth 1 -type d -name \"*.y\" -mtime +`expr $Y_Hist \* 365` -print0 | xargs -0 -r $DRYRUN rm -r -f"
fi
fi
trap - ERR

#========================================================

if [ -z "$DRYRUN" ]; then
    rm -f "$LockPath"
fi

echo "\t $(TimeStamp) Done."

exit 0