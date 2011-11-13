#!/bin/sh

#==============================================================================
#  Copyright 2011 Ido Magal. All rights reserved. 
#==============================================================================

# Store os for os-specific commands
OS=${OSTYPE//[0-9.]/}

if [ $OS == "darwin" ]; then
    rHOME="/private/var/root"
else
    rHOME="/root"
fi

# Directory where this script is located.
ScriptDir="$( cd -P "$( dirname "$0" )" && pwd )"

# File names and paths
ScriptPath="$ScriptDir/trunkfi.sh"
SettingsPath="$ScriptDir/trunkfish.cfg"
LockPath="$ScriptDir/~trunkfish_lock.pid"
ExcludesPath="$ScriptDir/~trunkfish_excludes.txt"
StdLogPath="$ScriptDir/~trunkfish.log"
ErrLogPath="$ScriptDir/~trunk_err.log"

# Load settings
. "$SettingsPath"

SSHKeyPath="$rHOME/.ssh/$SSHKey"

# Make sure only root can run our script
if [[ $EUID -ne 0 ]] && [[ $OS != "cygwin" ]]; then
   echo
   echo "\t This script requires root access."
   echo "\t Preface the command with 'sudo ', e.g. 'sudo ./trunkfi.sh --first-time'"
   echo
   exit 1
fi

# Abort if the LockPath exists
if [ -e $LockPath ]; then
    echo "\t $(TimeStamp) Lock file exists, which means the previous backup did not end gracefully. Delete $LockPath and retry."
    exit 1
fi

if [ ! -e "$SettingsPath" ]; then
    echo "\t $SettingsPath is missing. Cannot continue."
    exit 1
fi

#==============================================================================
# INSTALLATION ROUTINES

function first_time(){

    echo "In order to automate backups, we need to be able to ssh into the server without a password. Would you like me to set up password-less ssh now?"
    read SETUPSSH_YN
    if [ "$SETUPSSH_YN" = "y" ]; then
        setup_ssh
    else
        echo "You can set up password-less ssh later by typing 'sudo ./trunkfi.sh --setup-ssh'"
    fi

    echo "In order to automate backups, you need to create a daemon that will run in the backround. Would you like to do so now?"
    read SCHEDULE_YN
    if [ "$SCHEDULE_YN" = "y" ]; then
        schedule_launchd
        echo "You can disable the backup daemon later by typing 'sudo ./trunkfi.sh --unschedule'"
    else
        echo "You can set up a daemon later by running 'sudo ./trunkfi.sh --schedule"
    fi

    echo "Before you can automate backups, you'll need to back up once manually. Do you want to do this now?"
    read BACKUPNOW_YN
    if [ "$BACKUPNOW_YN" = "y" ]; then
        NEWBACKUP=1
    else
        echo "You can backup once manually by typping 'sudo ./trunkfi.sh -new'"
        exit 0
    fi
}

function setup_ssh(){

    ThisUser=$(id -u -n)

    ThisComputer=$(hostname)
    
    echo
    echo "\t The purpose of this script is to allow you to connect to $Server"
    echo "\t without requiring entering the SSH password every time, since it is"
    echo "\t expected that you'll want to automate the backups."
    echo
    echo "\t It will create a key for the root user on this machine to SSH as"
    echo "\t $ServerUser into $Server in order to do the backups."
    echo
    echo "\t In order to do that, we'll need to SSH a few times into $Server, and"
    echo "\t you'll need to provide the password for $ServerUser on $Server several times."
    echo
    read -p "Press enter to start or Ctrl-C to exit..."
    echo
    
    echo "\t Searching for $AuthorizedKeys on $Server."
    echo
    if [ 0 -ne `ssh -i "$SSHKeyPath" ${ServerUser}@${Server} test -f "$AuthorizedKeys" ;echo \$?` ]; then
        echo
        echo "\t $ServerUser@$Server doesn't have a $AuthorizedKeys file."
        echo
        $DRYRUN ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "mkdir ~/.ssh" 2> /dev/null
        echo
        echo "\t Creating $AuthorizedKeys on $Server."
        echo
        $DRYRUN ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "touch "$AuthorizedKeys""
        echo
    else
        echo
        echo "\t $AuthorizedKeys exists."
        echo "\t Searching for an entry for ${ThisUser}@${ThisComputer} in $HOME/.ssh/authorized_keys."
        echo
        if [ `ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "grep -c ${ThisUser}@${ThisComputer} "$AuthorizedKeys""` -gt 0 ]; then
            echo
            echo "\t ${ThisUser}@${ThisComputer} is already set to ssh without passwords to ${ServerUser}@${Server}."
            echo
            exit 1
        else
            echo
            echo "\t ${ThisUser}@${ThisComputer} doesn't have an entry in $HOME/.ssh/authorized_keys."
            echo "\t Let's add one."
            echo
        fi
    fi
    
    if [ 0 -eq `eval test -f $SSHKeyPath.pub; echo \$?` ]; then
        echo
        echo "\t I found an existing public key here: $SSHKeyPath.pub."
        echo "\t I will copy it onto the Server."
        echo
    else
        echo
        echo "\t I didn't find a public key for you. You will need to generate one."
        echo "\t I'm going to create one for you."
        echo 
        $DRYRUN ssh-keygen -t rsa -N '' -f "$SSHKeyPath"
    fi
    
    $DRYRUN rsync --rsync-path="$RsyncPath" -e 'ssh -i "$SSHKeyPath"' "$SSHKeyPath".pub ${ServerUser}@${Server}:~/.ssh/tmp
    $DRYRUN ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "echo >> "$AuthorizedKeys" && cat ~/.ssh/tmp >> "$AuthorizedKeys" && rm ~/.ssh/tmp"
    
    echo
    echo "\t You should now be able to ssh into ${ServerUser}@${Server} as root without password prompt."
    echo
    echo "\t To try it, type:"
    echo
    echo "\t\tsudo ssh -i "$SSHKeyPath" ${ServerUser}@${Server}"
    echo
    echo "\t Type \"exit\" when you're done."
    echo
}

function reset_launchd(){
    $DRYRUN launchctl stop com.trunkfish.backup 2>/dev/null
    $DRYRUN launchctl unload "$PlistPath" 2>/dev/null
}

function uninstall_launchd(){
    reset_launchd
    rm -f $PlistPath
}

function schedule_launchd(){

    echo "Enter an hour of day to backup. Valid values are '0' to '23' where 0 is midnight and 23 is 11pm."
    read PlistHour

    Plist="
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
        <plist version=\"1.0\">
        <dict>
        <key>Label</key>
        <string>com.trunkfish.backup</string>

        <key>ProgramArguments</key>
        <array>
        <string>/bin/sh</string>
        <string>"$ScriptPath"</string>
        </array>

        <key>StartCalendarInterval</key>
        <dict>
        <key>Hour</key>
        <integer>$PlistHour</integer>
        <key>Minute</key>
        <integer>0</integer>
        </dict>
        </dict>
        </plist>
        "
    if [ -z "$DRYRUN" ]; then
        echo "$Plist" > "$PlistPath"
    else
        echo "$Plist"
    fi

    reset_launchd
    $DRYRUN launchctl load "$PlistPath"
    $DRYRUN launchctl start com.trunkfish.backup
}

#==============================================================================
# If backup fails, delete partial backup and clean up.
function trap_backup() {
    trap - ERR
    echo "\t $(TimeStamp) Backup aborted. Cleaning up and deleting lock..."
    $DRYRUN ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "mv ${RemotePath}.incomplete ${RemotePath}.aborted.$$" &>/dev/null
    $DRYRUN ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "nohup rm -r -f ${RemotePath}.aborted.$$ &" &>/dev/null

    # save the logs of the failed backup  
    $DRYRUN mv $StdLogPath $ScriptDir"/"~TRUNKFISH_FAILED."${Today}".log &>/dev/null
    $DRYRUN mv $StdErr $ScriptDir"/"~TRUNK_ERR_FAILED."${Today}".log &>/dev/null
    $DRYRUN rm "$LockPath" &>/dev/null
    exit 1
}
#==============================================================================

for var in "$@"; do
    case "$var" in

        --dry-run)      DRYRUN="echo DRY RUN: -- "; NOLOGS=1;;

        --nologs)       NOLOGS=1;;

        --setup-ssh)    setup_ssh; exit 0;;

        --schedule)     schedule_launchd; exit 0;;

        --unschedule)   uninstall_launchd; exit 0;;

        --new)          NEWBACKUP=1;;

        --first-time)   first_time;;

        *) 
        echo
        echo "Valid options:"
        echo
        echo "--first-time  Use this to setup your routine backups."
        echo "--schedule    Starts a daemon that runs trunkfish every day at a certain hour."
        echo "--unschedule  Disable the daily scheduled backup daemon."
        echo "--new         Backup without attempting to link to a previous backup."
        echo "--dry-run     Use this to confirm the script is set up correctly. Nothing will actually execute."
        echo
        exit 1;;
    esac
done

# copy filters from Settings into an exclude file for rsync.
if [ -z "$DRYRUN" ]; then
    echo "$RsyncFilter" > $ExcludesPath
fi

# number of days to search back for a backup to link to before giving up.
SearchDays=30

# Today
Today=$(date +$DateFormat)

# Full backup path ( dir/date )
RemotePath=$RemoteDir"/"$Today

# Temp variable for searching previous backup
_days=1

# Last backup
if [ $OS == "darwin" ]; then
    PrevDate=$(date -v -${_days}d +"$DateFormat")
else
    PrevDate=$(date -d "-${_days} day" +"$DateFormat")
fi

# Validate directories
if [ ! -e "$BackupDir" ]; then
    echo "\t $(TimeStamp) The directory you are attempting to back up, \"$BackupDir\", does not exist."
    exit 1
fi
if [ 0 -ne `ssh -i "$SSHKeyPath" ${ServerUser}@${Server} test -d "$RemoteDir" ;echo \$?` ]; then
    echo "\t $(TimeStamp) $RemoteDir does not exist. If you're backing up to a DroboFS, use the Dashboard to create the Share."
    exit 1
fi
if [ 0 -ne `ssh -i "$SSHKeyPath" ${ServerUser}@${Server} test -f "$RsyncPath" ;echo \$?` ]; then
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

if [ -z $NEWBACKUP ]; then 
    echo "\t $(TimeStamp) Searching for the most recent backup, to which we're going to link today's backup..."
fi

# Check if there already exists a backup for today. If so, move it to ".incomplete" and backup into it, picking up whatever has changed since.
TodaysDir=`ssh -i "$SSHKeyPath" ${ServerUser}@${Server} find $RemoteDir -maxdepth 1 -regex ".*${Today}\.[dwmy]" | awk -F/ '{ print $NF }'`
if [ -n "$TodaysDir" ]; then
    echo "\t $(TimeStamp) There already exists a backup for today: ${Today}. I will update it."
    $DRYRUN ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "mv ${RemoteDir}/${TodaysDir} ${RemoteDir}/${TodaysPath}.incomplete"
fi

while [ -z "$NEWBACKUP" ]; do
    PrevDir=`ssh -i "$SSHKeyPath" ${ServerUser}@${Server} find $RemoteDir -maxdepth 1 -regex ".*${PrevDate}\.[dwmy]" | awk -F/ '{ print $NF }'`
    if [ -z "$PrevDir" ]; then
        _days=`expr $_days + 1`
        if [ ${SearchDays} -eq ${_days} ]; then
            echo "I can't find a previous backup less than $SearchDays days old."
            echo "Is this your first backup?"
            echo "Yes: Start a fresh backup with no linking."
            echo "No:  Keep searching for an even older backup."
            select yn in "Yes" "No"; do
                case $yn in
                    Yes) NEWBACKUP=1; break;;
                    No ) SearchDays=`expr $SearchDays + $SearchDays`; echo $SearchDays; break;;
                esac; done
        fi
        PrevDate=$(date -v -${_days}d +"$DateFormat")
    else
        break
    fi
done

if [ -n "$NEWBACKUP" ]; then
    PrevDate=""
fi

#========================================================
# Print working variables for debugging and the logs
#========================================================
echo
echo ------------------------------------------------------------------------------
echo Working variables
echo ------------------------------------------------------------------------------
echo "Today's date:  $Today"
echo "Last backup:   $PrevDate"
echo "Backing up:    $BackupDir"
echo "Destination:   $RemoteDir"/"$TodaysDir"
echo "Link Dest:     $RemoteDir"/"$PrevDir"
echo "Server user:   $ServerUser"
echo "Server:        $Server"
echo "Output Log:    $StdLogPath"
echo "Error Log:     $ErrLogPath"
echo "Lock File:     $LockPath"
echo "SSH Key File:  $SSHKeyPath"
echo "Excludes File: $ExcludesPath"
echo ------------------------------------------------------------------------------
echo
echo "Exclusions:"
cat $ExcludesPath
echo

#========================================================
# BACKUP happens here.
#========================================================
# Use trap to delete the partial backup if it doesn't complete.
# If we don't delete it, the next backup will generate lots of duplicate files because it will link to this partial directory. We'd rather it link to the previous good backup.

RsyncSSH="ssh -i $SSHKeyPath"

RsyncOptions=(
    --stats
    --force
    --delete-excluded
    --exclude-from="$ExcludesPath"
    --delete
    -aH
    --rsync-path="$RsyncPath"
    --out-format="%t %i %f%L"
    --link-dest=../"$PrevDir"
    -e "$RsyncSSH"
)

RsyncErr=(
    1 # Syntax or usage error
    2 # Protocol incompatibility
    3 # Errors selecting input/output files, dirs
    4 # Requested action not supported: an attempt was made to manipulate 64-bit files on a platform that cannot support them; or an option was specified that is supported by the client and not by the server.
    5 # Error starting client-server protocol
    10 # Error in socket I/O
    11 # Error in file I/O
    12 # Error in rsync protocol data stream
    13 # Errors with program diagnostics
    14 # Error in IPC code
    20 # Received SIGUSR1 or SIGINT
    21 # Some error returned by waitpid()
    22 # Error allocating core memory buffers
    23 # Partial transfer due to error
#     24 # Partial transfer due to vanished source files
    30 # Timeout in data send/receive
    135 # Unexplained error
)

trap trap_backup $RsyncErr
$DRYRUN rsync "${RsyncOptions[@]}" "$BackupDir" ${ServerUser}@${Server}:${RemotePath}.incomplete/
trap - $RsyncErr

# backup was successful. Rename it with an appropriate extension (d, w, m, or y)

Ext="d"

if [ 0 -ne $W_Hist ]; then
    if [ -z "`ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "find "$RemoteDir" -type d -name "*.w" -maxdepth 1 -mtime -7"`" ]; then
        echo "\t $(TimeStamp) Saving it as a weekly backup..."
        Ext="w"
    fi
fi
if [ 0 -ne $M_Hist ]; then
    if [ -z "`ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "find "$RemoteDir" -type d -name "*.m" -maxdepth 1 -mtime -30"`" ]; then
        echo "\t $(TimeStamp) Saving it as a monthly backup..."
        Ext="m"
    fi
fi
if [ 0 -ne $Y_Hist ]; then
    if [ -z "`ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "find "$RemoteDir" -type d -name "*.y" -maxdepth 1 -mtime -365"`" ]; then
        echo "\t $(TimeStamp) Saving it as a yearly backup..."
        Ext="y"
    fi
fi

echo "\t $(TimeStamp) backup completed successfully. Renaming ${RemotePath}.incomplete to ${RemotePath}.$Ext"
$DRYRUN ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "mv ${RemotePath}.incomplete ${RemotePath}.$Ext"

# Backup is done. Copy the logs into the backup dir.
if [ -z $NOLOGS ]; then
    echo "\t $(TimeStamp) Copying the logs..."
    $DRYRUN rsync --rsync-path="$RsyncPath" -e "$RsyncSSH" "$StdLogPath" ${ServerUser}@${Server}:${RemotePath}.$Ext/
    $DRYRUN rsync --rsync-path="$RsyncPath" -e "$RsyncSSH" "$ErrLogPath" ${ServerUser}@${Server}:${RemotePath}.$Ext/
fi



#========================================================
# Clean up old backups
#========================================================

trap "exit 1" ERR
if [ -z $NEWBACKUP ]; then
    if [ $D_Hist -gt -1 ]; then 
        echo "\t $(TimeStamp) Searching for daily backups older than $D_Hist days to delete..."
        ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "nohup find "$RemoteDir" -maxdepth 1 -type d -name \"*.d\" -mtime +$D_Hist -print0 | xargs -0 -r $DRYRUN rm -r -f &"
    fi
    if [ $W_Hist -gt -1 ]; then
        echo "\t $(TimeStamp) Searching for weekly backups older than $W_Hist weeks to delete..."
        ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "nohup find "$RemoteDir" -maxdepth 1 -type d -name \"*.w\" -mtime +`expr $W_Hist \* 7` -print0 | xargs -0 -r $DRYRUN rm -r -f &"
    fi
    if [ $M_Hist -gt -1 ]; then
        echo "\t $(TimeStamp) Searching for monthly backups older than $M_Hist weeks to delete..."
        ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "nohup find "$RemoteDir" -maxdepth 1 -type d -name \"*.m\" -mtime +`expr $M_Hist \* 30` -print0 | xargs -0 -r $DRYRUN rm -r -f &"
    fi
    if [ $Y_Hist -gt -1 ]; then
        echo "\t $(TimeStamp) Searching for yearly backups older than $Y_Hist years to delete..."
        ssh -i "$SSHKeyPath" ${ServerUser}@${Server} "nohup find "$RemoteDir" -maxdepth 1 -type d -name \"*.y\" -mtime +`expr $Y_Hist \* 365` -print0 | xargs -0 -r $DRYRUN rm -r -f &"
    fi
fi
trap - ERR

#========================================================

if [ -z "$DRYRUN" ]; then
    rm -f "$LockPath"
fi

echo "\t $(TimeStamp) Done."

exit 0
