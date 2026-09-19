#!/bin/bash

# ============================================================
# REAPER Keyboard Shortcuts Merge Helper
#
# macOS / Linux
#
# Argument:
#   $1 = REAPER Resource Path
#
# Waits for REAPER to close, copies the merged keymap
# (Data/reaper-kb.merged.ini, prepared by
# Daniel_Merge keyboard shortcuts.lua) over reaper-kb.ini,
# then relaunches REAPER.
#
# This helper is separate from Daniel_Restore_ini_files.sh
# and does not touch any personal settings.
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

DATA_FOLDER="$RESOURCE_PATH/Data"

KB_MERGED="$DATA_FOLDER/reaper-kb.merged.ini"
KB_TARGET="$RESOURCE_PATH/reaper-kb.ini"

# ============================================================
# DETERMINE OPERATING SYSTEM
# ============================================================

OS="$(uname)"

# ============================================================
# DETERMINE REAPER PROCESS
# ============================================================

REAPER_PID=""
REAPER_EXECUTABLE=""

if [ "$OS" = "Darwin" ]; then

# --------------------------------------------------------
# macOS
# --------------------------------------------------------

REAPER_PROCESS="REAPER"

REAPER_PID="$(pgrep -x "$REAPER_PROCESS" | head -n 1)"

elif [ "$OS" = "Linux" ]; then

# --------------------------------------------------------
# Linux
# --------------------------------------------------------

REAPER_PROCESS="reaper"

# Find the currently running REAPER process.
# This does NOT depend on REAPER being in PATH.
REAPER_PID="$(pgrep -x "$REAPER_PROCESS" | head -n 1)"

if [ -n "$REAPER_PID" ]; then

# Get the actual REAPER executable from /proc.
# This works even when REAPER is installed as a portable copy
# or is not present in the system PATH.
REAPER_EXECUTABLE="$(readlink -f "/proc/$REAPER_PID/exe" 2>/dev/null)"

if [ -z "$REAPER_EXECUTABLE" ] || [ ! -x "$REAPER_EXECUTABLE" ]; then
    echo "ERROR: Could not determine the REAPER executable."
    exit 1
fi

fi

else

echo "ERROR: Unsupported operating system: $OS"
exit 1

fi

# ============================================================
# VERIFY REAPER IS CURRENTLY RUNNING
# ============================================================

if [ -z "$REAPER_PID" ]; then
echo "ERROR: Could not find the running REAPER process."
exit 1
fi

echo "REAPER process found."
echo "PID: $REAPER_PID"

if [ "$OS" = "Linux" ]; then
echo "Executable: $REAPER_EXECUTABLE"
fi

# ============================================================
# WAIT FOR REAPER TO CLOSE
# ============================================================

echo ""
echo "Waiting for REAPER to close..."

while kill -0 "$REAPER_PID" 2>/dev/null; do
sleep 0.5
done

echo "REAPER has completely closed."

# ============================================================
# APPLY MERGED KEYBOARD SHORTCUTS
# ============================================================

if [ -f "$KB_MERGED" ]; then

echo ""
echo "Applying merged keyboard shortcuts..."

if cp -f "$KB_MERGED" "$KB_TARGET"; then
rm -f "$KB_MERGED"
echo "Keyboard shortcuts merged successfully."
else
echo "ERROR: Failed to apply merged keyboard shortcuts."
fi

else

echo ""
echo "reaper-kb.merged.ini not found - skipping."

fi

# ============================================================
# RELAUNCH REAPER
# ============================================================

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

# ============================================================
# FINISHED
# ============================================================

echo ""
echo "============================================"
echo "REAPER keyboard shortcuts merge completed."
echo "============================================"

exit 0
