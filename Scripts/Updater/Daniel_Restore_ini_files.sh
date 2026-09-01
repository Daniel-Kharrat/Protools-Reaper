#!/bin/bash

============================================================
REAPER File Restore Helper
macOS / Linux
Argument:
$1 = REAPER Resource Path
============================================================
============================================================
REAPER RESOURCE PATH
============================================================

RESOURCE_PATH="$1"

if [ -z "$RESOURCE_PATH" ]; then
echo "ERROR: REAPER resource path was not provided."
exit 1
fi

============================================================
PATHS
============================================================

PERSONAL_SETTINGS="$RESOURCE_PATH/Personal Settings"

SWS_SOURCE="$PERSONAL_SETTINGS/sws-autocoloricon.ini"
SWS_TARGET="$RESOURCE_PATH/sws-autocoloricon.ini"

SCREENSETS_SOURCE="$PERSONAL_SETTINGS/reaper-screensets.ini"
SCREENSETS_TARGET="$RESOURCE_PATH/reaper-screensets.ini"

============================================================
CHECK SOURCE FILES
============================================================

if [ ! -f "$SWS_SOURCE" ]; then
echo "ERROR: File not found:"
echo "$SWS_SOURCE"
exit 1
fi

if [ ! -f "$SCREENSETS_SOURCE" ]; then
echo "ERROR: File not found:"
echo "$SCREENSETS_SOURCE"
exit 1
fi

============================================================
DETERMINE OPERATING SYSTEM
============================================================

OS="$(uname)"

============================================================
DETERMINE REAPER PROCESS
============================================================

REAPER_PID=""
REAPER_EXECUTABLE=""

if [ "$OS" = "Darwin" ]; then

# --------------------------------------------------------
# macOS
# --------------------------------------------------------

REAPER_PROCESS="REAPER"

REAPER_PID="$(pgrep -x "$REAPER_PROCESS" | head -n 1)"

if [ -z "$REAPER_PID" ]; then
    echo "ERROR: Could not find the running REAPER process."
    exit 1
fi

elif [ "$OS" = "Linux" ]; then

# --------------------------------------------------------
# Linux
# --------------------------------------------------------

REAPER_PROCESS="reaper"

# Find the currently running REAPER process.
# This does NOT depend on REAPER being in PATH.
REAPER_PID="$(pgrep -x "$REAPER_PROCESS" | head -n 1)"

if [ -z "$REAPER_PID" ]; then
    echo "ERROR: Could not find the running REAPER process."
    exit 1
fi

# Get the actual REAPER executable from /proc.
# This works even when REAPER is installed as a portable copy
# or is not present in the system PATH.
REAPER_EXECUTABLE="$(readlink -f "/proc/$REAPER_PID/exe" 2>/dev/null)"

if [ -z "$REAPER_EXECUTABLE" ] || [ ! -x "$REAPER_EXECUTABLE" ]; then
    echo "ERROR: Could not determine the REAPER executable."
    exit 1
fi

else

echo "ERROR: Unsupported operating system: $OS"
exit 1

fi

============================================================
VERIFY REAPER IS CURRENTLY RUNNING
============================================================

if [ -z "$REAPER_PID" ]; then
echo "ERROR: Could not find the running REAPER process."
exit 1
fi

echo "REAPER process found."
echo "PID: $REAPER_PID"

if [ "$OS" = "Linux" ]; then
echo "Executable: $REAPER_EXECUTABLE"
fi

============================================================
WAIT FOR REAPER TO CLOSE
============================================================

echo ""
echo "Waiting for REAPER to close..."

while kill -0 "$REAPER_PID" 2>/dev/null; do
sleep 0.5
done

echo "REAPER has completely closed."

============================================================
RESTORE SWS AUTO COLOR / ICON
============================================================

echo ""
echo "Restoring sws-autocoloricon.ini..."

if cp -f "$SWS_SOURCE" "$SWS_TARGET"; then
echo "SWS auto color restored successfully."
else
echo "ERROR: Failed to restore sws-autocoloricon.ini."
exit 1
fi

============================================================
RESTORE REAPER SCREENSETS
============================================================

echo ""
echo "Restoring reaper-screensets.ini..."

if cp -f "$SCREENSETS_SOURCE" "$SCREENSETS_TARGET"; then
echo "REAPER screensets restored successfully."
else
echo "ERROR: Failed to restore reaper-screensets.ini."
exit 1
fi

============================================================
RELAUNCH REAPER
============================================================

echo ""
echo "Launching REAPER..."

if [ "$OS" = "Darwin" ]; then

# --------------------------------------------------------
# macOS
# --------------------------------------------------------

open -a "REAPER"

elif [ "$OS" = "Linux" ]; then

# --------------------------------------------------------
# Linux
# --------------------------------------------------------

"$REAPER_EXECUTABLE" >/dev/null 2>&1 &

fi

============================================================
FINISHED
============================================================

echo ""
echo "============================================"
echo "REAPER file restore completed successfully."
echo "============================================"

exit 0
