#!/bin/bash

# ============================================================
# REAPER File Restore Helper
#
# macOS / Linux
#
# Argument:
#   $1 = REAPER Resource Path
# ============================================================


# ============================================================
# REAPER RESOURCE PATH
# ============================================================

RESOURCE_PATH="$1"

if [ -z "$RESOURCE_PATH" ]; then
    echo "ERROR: REAPER resource path was not provided."
    exit 1
fi


# ============================================================
# PATHS
# ============================================================

PERSONAL_SETTINGS="$RESOURCE_PATH/Personal Settings"

SWS_SOURCE="$PERSONAL_SETTINGS/sws-autocoloricon.ini"
SWS_TARGET="$RESOURCE_PATH/sws-autocoloricon.ini"

SCREENSETS_SOURCE="$PERSONAL_SETTINGS/reaper-screensets.ini"
SCREENSETS_TARGET="$RESOURCE_PATH/reaper-screensets.ini"


# ============================================================
# CHECK SOURCE FILES
# ============================================================

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


# ============================================================
# DETERMINE OPERATING SYSTEM
# ============================================================

OS="$(uname)"


# ============================================================
# DETERMINE REAPER PROCESS
# ============================================================

if [ "$OS" = "Darwin" ]; then

    # macOS REAPER process name
    REAPER_PROCESS="REAPER"

elif [ "$OS" = "Linux" ]; then

    # Linux REAPER process name
    REAPER_PROCESS="reaper"

    # Find REAPER executable for relaunch
    REAPER_EXECUTABLE="$(command -v reaper)"

    if [ -z "$REAPER_EXECUTABLE" ]; then
        echo "ERROR: Could not find 'reaper' in PATH."
        exit 1
    fi

else

    echo "ERROR: Unsupported operating system: $OS"
    exit 1

fi


# ============================================================
# VERIFY REAPER IS CURRENTLY RUNNING
# ============================================================

if ! pgrep -x "$REAPER_PROCESS" > /dev/null 2>&1; then
    echo "ERROR: Could not find the running REAPER process."
    exit 1
fi


# ============================================================
# WAIT FOR REAPER TO CLOSE
# ============================================================

echo "Waiting for REAPER to close..."

while pgrep -x "$REAPER_PROCESS" > /dev/null 2>&1; do
    sleep 0.5
done

echo "REAPER has completely closed."


# ============================================================
# RESTORE SWS AUTO COLOR / ICON
# ============================================================

echo "Restoring sws-autocoloricon.ini..."

if cp -f "$SWS_SOURCE" "$SWS_TARGET"; then
    echo "SWS auto color restored successfully."
else
    echo "ERROR: Failed to restore sws-autocoloricon.ini."
    exit 1
fi


# ============================================================
# RESTORE REAPER SCREENSETS
# ============================================================

echo "Restoring reaper-screensets.ini..."

if cp -f "$SCREENSETS_SOURCE" "$SCREENSETS_TARGET"; then
    echo "REAPER screensets restored successfully."
else
    echo "ERROR: Failed to restore reaper-screensets.ini."
    exit 1
fi


# ============================================================
# RELAUNCH REAPER
# ============================================================

echo "Launching REAPER..."

if [ "$OS" = "Darwin" ]; then

    # macOS
    open -a "REAPER"

elif [ "$OS" = "Linux" ]; then

    # Linux
    "$REAPER_EXECUTABLE" >/dev/null 2>&1 &

fi


# ============================================================
# FINISHED
# ============================================================

echo ""
echo "============================================"
echo "REAPER file restore completed successfully."
echo "============================================"

exit 0
