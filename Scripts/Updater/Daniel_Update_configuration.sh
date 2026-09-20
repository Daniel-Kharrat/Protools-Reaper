#!/bin/bash

# ============================================================
# REAPER Configuration Update Helper
#
# macOS / Linux
#
# Arguments:
#   $1 = REAPER Resource Path
#   $2 = REAPER executable (Linux only; used if it cannot be detected)
#
# Waits for REAPER to close, copies the files prepared by
# Daniel_Update configuration.lua (Data/Daniel Kharrat/Update) into
# the resource folder, then relaunches REAPER.
#
# This helper is separate from Daniel_Restore_ini_files.sh
# and Daniel_Merge_keyboard_shortcuts.sh.
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

STAGE="$DAN_FOLDER/Update"
EXTRACTED="$STAGE/extracted"

INI_MERGED="$STAGE/reaper.ini.merged"
INI_TARGET="$RESOURCE_PATH/reaper.ini"

KB_MERGED="$STAGE/reaper-kb.merged.ini"
KB_TARGET="$RESOURCE_PATH/reaper-kb.ini"

VERSION_SOURCE="$STAGE/applied_version.txt"
VERSION_TARGET="$DAN_FOLDER/Config_Version.txt"

# Log file (kept, so a failed update can be diagnosed)
LOG="$DAN_FOLDER/Update_Log.txt"
REAPER_EXE_ARG="$2"

log() {
echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null
}

FAILED=0

log "Helper started. Resource path: $RESOURCE_PATH"

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
    log "ERROR: could not determine the REAPER executable."
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
log "REAPER process not found - it has probably already closed."
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
log "REAPER has closed."

# ============================================================
# APPLY THE UPDATE
# ============================================================

if [ ! -d "$STAGE" ]; then

echo ""
echo "Nothing to apply - $STAGE not found."

else

# --------------------------------------------------------
# Files that are replaced as they are
# --------------------------------------------------------

if [ -d "$EXTRACTED" ]; then

echo ""
echo "Copying configuration files..."

# cp -R copies file by file into the existing folders: it replaces files with the
# same name and leaves any other file (for example other icons) alone.
if cp -R "$EXTRACTED/." "$RESOURCE_PATH/"; then
echo "Configuration files copied successfully."
else
echo "ERROR: Failed to copy the configuration files."
FAILED=1
fi

fi

# --------------------------------------------------------
# reaper.ini (merged)
# --------------------------------------------------------

if [ -f "$INI_MERGED" ]; then

echo ""
echo "Applying merged reaper.ini..."

if cp -f "$INI_MERGED" "$INI_TARGET"; then
echo "reaper.ini updated successfully."
else
echo "ERROR: Failed to apply merged reaper.ini."
FAILED=1
fi

fi

# --------------------------------------------------------
# reaper-kb.ini (merged keyboard shortcuts)
# --------------------------------------------------------

if [ -f "$KB_MERGED" ]; then

echo ""
echo "Applying merged keyboard shortcuts..."

if cp -f "$KB_MERGED" "$KB_TARGET"; then
echo "Keyboard shortcuts merged successfully."
else
echo "ERROR: Failed to apply merged keyboard shortcuts."
FAILED=1
fi

fi

# --------------------------------------------------------
# Record the version and clean up
# --------------------------------------------------------

if [ "$FAILED" -eq 0 ]; then

cp -f "$VERSION_SOURCE" "$VERSION_TARGET" 2>/dev/null
rm -rf "$STAGE"

else

echo ""
echo "Some files could not be applied. The prepared files were kept in:"
echo "$STAGE"

fi

fi

# ============================================================
# RELAUNCH REAPER
# ============================================================

echo ""
echo "Launching REAPER..."
log "Launching REAPER (failed=$FAILED)"

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
echo "REAPER configuration update completed."
else
echo "REAPER configuration update finished with errors."
fi
echo "============================================"

exit 0
