#!/bin/sh

PlistPath="/Library/LaunchDaemons/com.trunkfish.backup.plist"

Hour=0

Plist="
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>com.trunkfish.backup</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>"$ScriptPath"</string>
    </array>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$Hour</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
"
if [ -z "$DRYRUN" ]; then
    echo "$Plist" > "$PlistPath"
fi

$DRYRUN launchctl stop com.trunkfish.backup 2>/dev/null
$DRYRUN launchctl unload "$PlistPath" 2>/dev/null
$DRYRUN launchctl load "$PlistPath"
$DRYRUN launchctl start com.trunkfish.backup