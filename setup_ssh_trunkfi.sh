#!/bin/sh

#  setup_drobofs.sh
#  
#
#  Created by Ido Magal on 10/10/11.
#  Copyright 2011 Ido Magal. All rights reserved.

ThisUser=$(id -u -n)

ThisComputer=$(hostname)

echo
echo "\t The purpose of this script is to allow you to connect to the Server"
echo "\t without requiring entering the SSH password every time, since it is"
echo "\t expected that you'll want to automate the backups."
echo
echo "\t It will create a key for the root user on this machine to SSH as"
echo "\t $ServerUser into $Server in order to do the backups."
echo
echo "\t In order to do that, we'll need to SSH a few times into Server, and"
echo "\t you'll need to provide the password for $ServerUser on $Server several times."
echo
read -p "Press enter to start or Ctrl-C to exit..."
echo

echo "\t Searching for ~/.ssh/authorized_keys on the Server."
if [ -1 -eq `ssh ${ServerUser}@${Server} test -d "$AuthorizedKeys" ;echo \$?` ]; then
    echo "\t $ServerUser@$Server doesn't have a $AuthorizedKeys file. I'll make one."
    echo "\t Creating ~/.ssh on Server."
    $DRYRUN ssh ${ServerUser}@${Server} "mkdir ~/.ssh"
    echo "\t Creating $AuthorizedKeys on Server."
    $DRYRUN ssh ${ServerUser}@${Server} "touch "$AuthorizedKeys""
else
    echo "\t Searching for an entry for ${ThisUser}@${ThisComputer} in ~/.ssh/authorized_keys."
    if [ `ssh ${ServerUser}@${Server} "grep -c ${ThisUser}@${ThisComputer} "$AuthorizedKeys""` -gt 0 ]; then
        echo "\t ${ThisUser}@${ThisComputer} is already set to ssh without passwords to ${ServerUser}@${Server}."
        echo
    exit 1
    fi
fi

if [ -e $PubKey ]; then
    echo
    echo "\t I found an existing public key here: $PubKey."
    echo "\t I will copy it onto the Server."
else
    echo
    echo "\t I didn't find a public key for you. You will need to generate one."
    echo "\t I'm going to execute '$SSHKeyGen' for you. Follow the prompts."
    echo "\t I recommend just hitting enter to get the defaults."
    echo "\t If you pick a non-default location for the key file, you'll need to"
    echo "\t edit this script, since I assume it's "$PubKey" and attempt to"
    echo "\t copy it from there."
    $DRYRUN SSHKeyGen
fi

$DRYRUN rsync --rsync-path="$RsyncPath" -e 'ssh -p 22' "$PubKey" ${ServerUser}@${Server}:~/.ssh/tmp
$DRYRUN ssh ${ServerUser}@${Server} "echo >> "$AuthorizedKeys" && cat ~/.ssh/tmp >> "$AuthorizedKeys" && rm ~/.ssh/tmp"

echo
echo "\t If there weren't any errors, you should now be able to ssh into ${ServerUser}@${Server} without password prompt."
echo
echo "\t To try it, type \"ssh ${ServerUser}@${Server}\" at the command prompt."
echo "\t There should be no password prompt."
echo "\t Type \"exit\" when you're done."
echo
exit 0
