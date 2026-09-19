#!/bin/bash

# ============================================================
# REAPER Configuration Update Helper
#
# macOS / Linux
#
# Argument:
#   $1 = REAPER Resource Path
#
# Waits for REAPER to close, copies the files prepared by
# Daniel_Update configuration.lua (Data/Daniel_Update) into
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

STAGE="$DATA_FOLDER/Daniel_Update"
EXTRACTED="$STAGE/extracted"

INI_MERGED="$STAGE/reaper.ini.merged"
INI_TARGET="$RESOURCE_PATH/reaper.ini"

KB_MERGED="$STAGE/reaper-kb.merged.ini"
KB_TARGET="$RESOURCE_PATH/reaper-kb.ini"

VERSION_SOURCE="$STAGE/applied_version.txt"
VERSION_TARGET="$DATA_FOLDER/Daniel_Config_Version.txt"

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
