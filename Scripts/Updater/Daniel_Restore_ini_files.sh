#!/bin/bash

# ============================================================
# REAPER Restore Helper
#
# macOS / Linux
#
# Arguments:
#   $1 = REAPER Resource Path
#   $2 = REAPER executable (Linux only; used if it cannot be detected)
#
# Waits for REAPER to close, copies the files prepared by
# Daniel_Restore personal settings.lua
# (Data/Daniel Kharrat/Restore/files) into the resource folder,
# then relaunches REAPER.
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

DAN_FOLDER="$DATA_FOLDER/Daniel Kharrat"

STAGE="$DAN_FOLDER/Restore"
STAGED_FILES="$STAGE/files"

# The REAPER executable as passed by the Lua script (Linux; used if it cannot
# be detected)
REAPER_EXE_ARG="$2"

FAILED=0


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

fi

# If the executable could not be detected (or REAPER has already closed),
# use the one passed by the Lua script.
if [ -z "$REAPER_EXECUTABLE" ] || [ ! -x "$REAPER_EXECUTABLE" ]; then
    REAPER_EXECUTABLE="$REAPER_EXE_ARG"
fi

if [ -z "$REAPER_EXECUTABLE" ] || [ ! -x "$REAPER_EXECUTABLE" ]; then
    echo "ERROR: Could not determine the REAPER executable."
    exit 1
fi

else

echo "ERROR: Unsupported operating system: $OS"
exit 1

fi

# ============================================================
# VERIFY REAPER IS CURRENTLY RUNNING
# ============================================================

if [ -z "$REAPER_PID" ]; then
# REAPER may already have closed before this helper started: carry on.
echo "REAPER process not found - it has probably already closed."
else
echo "REAPER process found."
echo "PID: $REAPER_PID"

if [ "$OS" = "Linux" ]; then
echo "Executable: $REAPER_EXECUTABLE"
fi
fi

# ============================================================
# WAIT FOR REAPER TO CLOSE
# ============================================================

echo ""
echo "Waiting for REAPER to close..."

if [ -n "$REAPER_PID" ]; then
while kill -0 "$REAPER_PID" 2>/dev/null; do
sleep 0.5
done
fi

echo "REAPER has completely closed."

# ============================================================
# RESTORE THE FILES
# ============================================================

if [ ! -d "$STAGED_FILES" ]; then

echo ""
echo "Nothing to restore - the prepared files were not found."

else

echo ""
echo "Restoring files..."

# cp -R copies file by file into the existing folders
if cp -R "$STAGED_FILES/." "$RESOURCE_PATH/"; then
echo "Files restored successfully."
rm -rf "$STAGE"
else
echo "ERROR: Failed to restore the files."
FAILED=1
echo ""
echo "Some files could not be restored. The prepared files were kept in:"
echo "$STAGE"
fi

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
if [ "$FAILED" -eq 0 ]; then
echo "REAPER restore completed."
else
echo "REAPER restore finished with errors."
fi
echo "============================================"

exit 0
