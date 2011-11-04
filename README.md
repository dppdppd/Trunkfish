# Trunkfi.sh

Copyright 2011 Ido Magal. All rights reserved. M8R-u8t2l4 AT mailinator DOT com


    DISCLAIMER:

    USE AT YOUR OWN RISK. YOU ARE RESPONSIBLE FOR READING AND UNDERSTANDING
    THE CODE IN THIS SCRIPT AND NO GUARANTEE IS GIVEN OR IMPLIED.   
     
    THIS CODE MAY ERASE ANYTHING, ANYWHERE, AT ANY MOMENT.


## What is Trunkfish?

__Trunkfish__ is a script that creates periodic file backups of the machine executing it onto a separate machine. It was explicitly developed for backing up OSX machines onto a DroboFS, but, with some minimal work, should work for backing up any posix device onto any other posix device, provided they have the requisite programs. 


## Why Trunkfish?

I wrote __Trunkfish__ because I wanted a periodic hardlinked-based backup system that I could use to backup our home Macs onto the home DroboFS. The top contenders were TimeMachine and rsnapshot.

__Trunkfish__ is different from Time Machine in that it does not use a proprietary storage format. It creates a directory for each day dated as such (e.g. "/2011-11-1/") which contains a complete snapshot of the target directory on the host computer. The tradeoff is that it is not a system image backup, but a loose file backup.

__Trunkfish__ is different from rsnapshot in that it is client-driven and does not require running any software other than rsync and ssh on the server. Additionally, it's easier to setup (doesn't require multiple cron jobs and rsync configs), and it uses absolute dates for backup directories rather than relative ones.


## How do I use Trunkfish?

  1. First, read this README.
  2. _git clone git://github.com/idomagal/Trunkfish.git_
  3. Edit trunkfish.cfg to suit your backup.
  4. _sudo ./trunkfi.sh --first-time_


## What does Trunkfish consist of?

Files that go with this script:


    *  README.md               - This file.
    *  trunkfi.sh              - The main script that does the work.
    *  trunkfish.cfg           - The configuration file.
                                 You need to edit this file before you run trunkfi.sh.
    *  find_trunkfi.sh         - A script to identify when a file was was most recently updated.
                                 This is really only necessary when backing up to a DroboFS,
                                 since the 'find' on those doesn't support '-links'


Temporary files that get generated during every backup:

    *  ~trunkfish_excludes.txt - A temporary txt file that contains rsync filters for the backup.
    *  ~trunkfish.log          - A temporary log of the backup events.
    *  ~trunk_err.log          - A temporary log of backup errors, if there are any.


## What's the status of Trunkfish development?

TODO:
  
*  Require root for setup scripts
*  Create cfg on first run
*  Dynamically choose rsync exclusions based on OS
*  Add scheduling support for cygwin


