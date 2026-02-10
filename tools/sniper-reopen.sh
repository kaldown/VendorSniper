#!/bin/sh
# VendorSniper auto-reopen
# Presses F5 with random delay (2-5s) to reopen vendor window
# Make sure "Interact with Target" is bound to F5 in WoW settings
# Usage: ./sniper-reopen.sh [max_minutes]
#   default: 60 minutes

MAX_MINUTES=${1:-60}

echo "VendorSniper reopen script"
echo "  Pressing F5 every 2-5s (random) for ${MAX_MINUTES} minutes"
echo "  Press Ctrl+C to stop"
echo ""

osascript -e "
set endTime to (current date) + ($MAX_MINUTES * 60)
repeat while (current date) < endTime
    set d to (random number from 2 to 5)
    delay d
    tell application \"System Events\"
        key code 96
    end tell
end repeat
"

echo "Done."
