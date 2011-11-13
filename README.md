# Trunkfi.sh

Copyright 2011 Ido Magal. All rights reserved. M8R-u8t2l4 AT mailinator DOT com


    DISCLAIMER:

    USE AT YOUR OWN RISK. YOU ARE RESPONSIBLE FOR READING AND UNDERSTANDING
    THE CODE IN THIS SCRIPT AND NO GUARANTEE IS GIVEN OR IMPLIED.   
     
    THIS CODE MAY ERASE ANYTHING, ANYWHERE, AT ANY MOMENT.


## What is Trunkfish?

__Trunkfish__ is a script that creates periodic file backups of the machine executing it onto a separate machine. It was explicitly developed for backing up OSX machines onto a DroboFS, but, with some minimal work, should work on linux and cygwin'ed Windows machines. As of now, all but the scheduling works on cygwin. 


## Why Trunkfish?

I wrote __Trunkfish__ because I wanted a periodic hardlinked-based backup system that I could use to backup our home Macs onto the home DroboFS. The considered alternatives were TimeMachine and rsnapshot.

Unlike Time Machine, __Trunkfish__ does not use a sparsebundle filesystem image as a destination for the backup. The primary advantage is that it's not prone to total corruption like Time Machine was. I got fed up losing the entire backup, with all of its history, every time the lan hiccuped and the sparsebundle broke.

Not bound by a difficult-to-crack and fragile filesystem image, __Trunkfish__ simply creates a directory for each day dated as such (e.g. "/2011-11-1/") and puts a complete snapshot of the desired directory onto the server. No special software or scripting knowledge is necessary to browse the entire backup history. The directories are clearly labeled by date and can be browsed and explored with any file manager, such as Finder.

On the other hand, the relative disadvantages to __Trunkfish__ are that it does not preserve OSX metadata and it cannot restore an entire system image; only all of its files.

When I ran a home linux computer as a file server, I used rsnapshot to backup our home machines. For the most part I liked rsnapshot but I didn't like that it was server-driven, that it required the kind of setup on the client that I had to relearn every time I wanted to tweak it, and that the backups were uselessly named relative to the current day.

__Trunkfish__ isn't run or managed by the server (The server needs rsync and ssh, but otherwise doesn't know anything about the backing up) so one doesn't need to run the server; just have access to an account on a linux box. It's also easier to setup (doesn't require multiple cron jobs and rsync configs), and it uses absolute dates for backup directories rather than relative ones.


## How do I use Trunkfish?


#### How do I install Trunkfish?

  1. First, read this README.
  2. _git clone git://github.com/idomagal/Trunkfish.git_
  3. Edit trunkfish.cfg to suit your backup.
  4. _sudo ./trunkfi.sh --first-time_

#### How can I watch Trunkfish progress?

_tail -f ~trunkfish.log_

#### How do I know if the backup succeeded?

  * If the backup failed, there will be a directory with a .incomplete or .aborted extension in your backup dir. You can safely delete them.
  * Look at ~trunk_err.log to determine what may have gone wrong.
  * Otherwise, if the backup was successful, there'll be a directory named with date and a .d, .w, .m, and or .y extensions. E.g. '2011-11-31.d'

#### What does the .d, .w, .m, and .y extensions mean?

They represent daily, weekly, monthly, and yearly backups, respectively. Eventually the more frequent backup directories get deleted and only the less frequent ones remain, in order to conserve space. By default __Trunkfish__ keeps 30 daily backups, 26 weekly backups, and never deletes monthly or yearly backups. You can change these numbers in trunkfish.cfg.

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
  
* OSX-specific: Backup into a sparsebundle to preserve OSX metadata
* Create cfg on first run
* Dynamically choose rsync exclusions based on OS
* Add scheduling support for cygwin
* Add versioning to the script

