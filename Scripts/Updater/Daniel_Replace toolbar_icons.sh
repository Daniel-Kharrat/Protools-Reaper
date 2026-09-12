#!/bin/bash

# ============================================================

# REAPER Toolbar Icons Updater

#

# macOS / Linux

#

# Argument:

# $1 = REAPER resource path

#

# Process:

# 1. Wait for REAPER to close

# 2. Download toolbar_icons.zip

# 3. Extract into temporary toolbar_icons folder

# 4. Verify extracted contents

# 5. Replace Data/toolbar_icons completely

# 6. Verify replacement

# 7. Clean up

# 8. Relaunch REAPER

# ============================================================

# ------------------------------------------------------------

# Configuration

# ------------------------------------------------------------

DOWNLOAD_URL="https://github.com/Daniel-Kharrat/Protools-Reaper/raw/refs/heads/master/MISC%20Data/toolbar_icons.zip"

RESOURCE_PATH="$1"

if [ -z "$RESOURCE_PATH" ]; then
echo "ERROR: REAPER resource path was not provided."
exit 1
fi

TARGET_DIR="$RESOURCE_PATH/Data/toolbar_icons"

CURL="/usr/bin/curl"
UNZIP="/usr/bin/unzip"

OS="$(uname)"

# ------------------------------------------------------------

# Validate operating system

# ------------------------------------------------------------

if [ "$OS" = "Darwin" ]; then


REAPER_PROCESS="REAPER"


elif [ "$OS" = "Linux" ]; then


REAPER_PROCESS="reaper"


else


echo "ERROR: Unsupported operating system: $OS"
exit 1


fi

# ------------------------------------------------------------

# Validate required programs

# ------------------------------------------------------------

if [ ! -x "$CURL" ]; then
echo "ERROR: curl not found at:"
echo "$CURL"
exit 1
fi

if [ ! -x "$UNZIP" ]; then
echo "ERROR: unzip not found at:"
echo "$UNZIP"
exit 1
fi

# ------------------------------------------------------------

# Create temporary working directory

# ------------------------------------------------------------

WORK_DIR="$(mktemp -d "$RESOURCE_PATH/.toolbar_icons_update.XXXXXX")"

if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ]; then
echo "ERROR: Could not create temporary working directory."
exit 1
fi

cleanup()
{
if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
rm -rf "$WORK_DIR"
fi
}

trap cleanup EXIT

ZIP_PATH="$WORK_DIR/toolbar_icons.zip"
NEW_TOOLBAR_DIR="$WORK_DIR/toolbar_icons"

# ------------------------------------------------------------

# Find running REAPER process

# ------------------------------------------------------------

REAPER_PID="$(pgrep -x "$REAPER_PROCESS" | head -n 1)"

if [ -z "$REAPER_PID" ]; then
echo "ERROR: Could not find the running REAPER process."
exit 1
fi

echo "REAPER process found."
echo "PID: $REAPER_PID"

# ------------------------------------------------------------

# Determine REAPER executable on Linux

# ------------------------------------------------------------

REAPER_EXECUTABLE=""

if [ "$OS" = "Linux" ]; then


REAPER_EXECUTABLE="$(readlink -f "/proc/$REAPER_PID/exe" 2>/dev/null)"

if [ -z "$REAPER_EXECUTABLE" ] || [ ! -x "$REAPER_EXECUTABLE" ]; then
    echo "ERROR: Could not determine the REAPER executable."
    exit 1
fi

echo "REAPER executable:"
echo "$REAPER_EXECUTABLE"


fi

# ------------------------------------------------------------

# Wait for REAPER to completely close

# ------------------------------------------------------------

echo ""
echo "Waiting for REAPER to close..."

while kill -0 "$REAPER_PID" 2>/dev/null; do
sleep 0.5
done

echo "REAPER has completely closed."

# ------------------------------------------------------------

# Download

# ------------------------------------------------------------

echo ""
echo "Downloading toolbar icons..."

if ! "$CURL" \
    -L \
    --fail \
    --silent \
    --show-error \
    -o "$ZIP_PATH" \
    "$DOWNLOAD_URL"
then


echo "ERROR: Toolbar icon download failed."
exit 1


fi

# ------------------------------------------------------------

# Verify ZIP exists

# ------------------------------------------------------------

if [ ! -s "$ZIP_PATH" ]; then
echo "ERROR: Downloaded ZIP is missing or empty."
exit 1
fi

echo "Download successful."

# ------------------------------------------------------------

# Create new toolbar_icons directory

# ------------------------------------------------------------

mkdir -p "$NEW_TOOLBAR_DIR"

if [ ! -d "$NEW_TOOLBAR_DIR" ]; then
echo "ERROR: Could not create temporary toolbar_icons directory."
exit 1
fi

# ------------------------------------------------------------

# Extract ZIP

#

# The ZIP contents are placed directly inside:

#

# temporary/toolbar_icons/

#

# ------------------------------------------------------------

echo ""
echo "Extracting toolbar icons..."

if ! "$UNZIP" \
    -q \
    -o \
    "$ZIP_PATH" \
    -d "$NEW_TOOLBAR_DIR"
then


echo "ERROR: ZIP extraction failed."
exit 1


fi

echo "Extraction successful."

# ------------------------------------------------------------

# Verify extracted toolbar icons

# ------------------------------------------------------------

PNG_COUNT="$(find "$NEW_TOOLBAR_DIR" -type f -iname "*.png" | wc -l | tr -d ' ')"

if [ "$PNG_COUNT" -eq 0 ]; then
echo "ERROR: No PNG files were found after extraction."
exit 1
fi

if [ ! -d "$NEW_TOOLBAR_DIR/150" ]; then
echo "ERROR: Extracted folder is missing the 150 directory."
exit 1
fi

if [ ! -d "$NEW_TOOLBAR_DIR/200" ]; then
echo "ERROR: Extracted folder is missing the 200 directory."
exit 1
fi

echo "Verification successful."
echo "PNG files found: $PNG_COUNT"
echo "150 directory found."
echo "200 directory found."

# ------------------------------------------------------------

# Verify target parent directory

# ------------------------------------------------------------

TARGET_PARENT="$RESOURCE_PATH/Data"

if [ ! -d "$TARGET_PARENT" ]; then


echo "ERROR: REAPER Data directory does not exist:"
echo "$TARGET_PARENT"

exit 1


fi

# ------------------------------------------------------------

# Replace existing toolbar_icons folder

# ------------------------------------------------------------

BACKUP_DIR="$TARGET_PARENT/.toolbar_icons_old"

echo ""
echo "Replacing existing toolbar_icons folder..."

# Remove any leftover backup from a previous failed operation.

if [ -e "$BACKUP_DIR" ]; then
rm -rf "$BACKUP_DIR"
fi

# Move the existing folder out of the way.

if [ -d "$TARGET_DIR" ]; then


if ! mv "$TARGET_DIR" "$BACKUP_DIR"; then
    echo "ERROR: Could not move the existing toolbar_icons folder."
    exit 1
fi


fi

# Move the newly extracted folder into place.

if ! mv "$NEW_TOOLBAR_DIR" "$TARGET_DIR"; then


echo "ERROR: Could not move the new toolbar_icons folder into place."

# Restore the old folder if possible.
if [ -d "$BACKUP_DIR" ]; then
    mv "$BACKUP_DIR" "$TARGET_DIR"
fi

exit 1


fi

# ------------------------------------------------------------

# Verify replacement

# ------------------------------------------------------------

echo ""
echo "Verifying new toolbar_icons folder..."

if [ ! -d "$TARGET_DIR" ]; then
echo "ERROR: New toolbar_icons folder does not exist."
exit 1
fi

PNG_COUNT_AFTER="$(find "$TARGET_DIR" -type f -iname "*.png" | wc -l | tr -d ' ')"

if [ "$PNG_COUNT_AFTER" -eq 0 ]; then
echo "ERROR: No PNG files found in the replaced folder."
exit 1
fi

if [ ! -d "$TARGET_DIR/150" ]; then
echo "ERROR: New toolbar_icons folder is missing 150."
exit 1
fi

if [ ! -d "$TARGET_DIR/200" ]; then
echo "ERROR: New toolbar_icons folder is missing 200."
exit 1
fi

echo "Replacement successful."
echo "PNG files now installed: $PNG_COUNT_AFTER"

# ------------------------------------------------------------

# Remove old backup

# ------------------------------------------------------------

if [ -d "$BACKUP_DIR" ]; then
rm -rf "$BACKUP_DIR"
fi

# ------------------------------------------------------------

# Wait before relaunch

# ------------------------------------------------------------

echo ""
echo "Waiting 3 seconds before relaunch..."
sleep 3

# ------------------------------------------------------------

# Relaunch REAPER

# ------------------------------------------------------------

echo ""
echo "Launching REAPER..."

if [ "$OS" = "Darwin" ]; then


open -a "REAPER"


elif [ "$OS" = "Linux" ]; then


"$REAPER_EXECUTABLE" >/dev/null 2>&1 &


fi

echo ""
echo "Toolbar icons updated successfully."
echo "REAPER relaunched."

exit 0
