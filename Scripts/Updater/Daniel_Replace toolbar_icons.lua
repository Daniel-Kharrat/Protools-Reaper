-------------------------------------------------
-- CONFIG
-------------------------------------------------

local DOWNLOAD_URL = "https://github.com/Daniel-Kharrat/Protools-Reaper/raw/refs/heads/master/MISC%20Data/toolbar_icons.zip"
local FOLDER_NAME_IN_ZIP = ""  -- folder name inside the zip; "" if icons sit at the zip root
local TARGET_SUBFOLDER = "Data/toolbar_icons"

-- macOS-only paths (matches the tested-working approach). Curl/unzip are always
-- at these locations on macOS, so we use full paths rather than relying on PATH.
local CURL = "/usr/bin/curl"
local UNZIP = "/usr/bin/unzip"

-- Generous timeout: on macOS the FIRST subprocess REAPER spawns can be slow
-- due to Gatekeeper security checks, so we give it plenty of room.
local TIMEOUT_MS = 120000

-------------------------------------------------
-- Paths
-------------------------------------------------

local resource_path = reaper.GetResourcePath()
local zip_path = resource_path .. "/__icon_update_temp.zip"
local extract_dir = resource_path .. "/__icon_update_temp"
local target_dir = resource_path .. "/" .. TARGET_SUBFOLDER

local function log(msg)
  reaper.ShowConsoleMsg(tostring(msg) .. "\n")
end

local function dir_has_files(path)
  return reaper.EnumerateFiles(path, 0) ~= nil or reaper.EnumerateSubdirectories(path, 0) ~= nil
end

-------------------------------------------------
-- Step 1: Download
-------------------------------------------------

local function download_zip()
  os.remove(zip_path) -- clear any stale leftover from a previous failed run

  local cmd = CURL .. " -L --fail --silent --show-error -o " ..
    string.format("%q", zip_path) .. " " .. string.format("%q", DOWNLOAD_URL)

  log("Downloading icons...")
  local output = reaper.ExecProcess(cmd, TIMEOUT_MS)
  log("curl output: " .. tostring(output))

  local file = io.open(zip_path, "rb")
  if file then
    file:close()
    return true
  end
  return false
end

-------------------------------------------------
-- Step 2: Extract
-------------------------------------------------

local function extract_zip()
  local cmd = UNZIP .. " -o " .. string.format("%q", zip_path) ..
    " -d " .. string.format("%q", extract_dir)

  log("Extracting icons...")
  local output = reaper.ExecProcess(cmd, TIMEOUT_MS)
  log("unzip output: " .. tostring(output))

  return dir_has_files(extract_dir)
end

-------------------------------------------------
-- Step 3: Replace the target folder
-------------------------------------------------

local function replace_folder()
  local source_dir = extract_dir
  if FOLDER_NAME_IN_ZIP ~= "" then
    source_dir = source_dir .. "/" .. FOLDER_NAME_IN_ZIP
  end

  if not dir_has_files(source_dir) then
    log("ERROR: expected extracted folder not found at: " .. source_dir)
    return false
  end

  reaper.ExecProcess("/bin/rm -rf " .. string.format("%q", target_dir), TIMEOUT_MS)
  local output = reaper.ExecProcess(
    "/bin/mv " .. string.format("%q", source_dir) .. " " .. string.format("%q", target_dir),
    TIMEOUT_MS)
  log("move output: " .. tostring(output))

  return dir_has_files(target_dir)
end

-------------------------------------------------
-- Step 4: Cleanup
-------------------------------------------------

local function cleanup()
  os.remove(zip_path)
  reaper.ExecProcess("/bin/rm -rf " .. string.format("%q", extract_dir), TIMEOUT_MS)
end

-------------------------------------------------
-- MAIN
-------------------------------------------------

reaper.ClearConsole()
log("=== Toolbar Icon Updater ===")
log("Resource path: " .. resource_path)
log("Target folder: " .. target_dir)

local final_message

if download_zip() then
  log("Download OK.")
  if extract_zip() then
    log("Extract OK.")
    if replace_folder() then
      final_message = "Toolbar icons updated successfully."
      log("\nDone. Restart REAPER or reopen the toolbar customize dialog to see the new icons.")
    else
      final_message = "ERROR: Failed to move the extracted folder into place. See console for details."
    end
  else
    final_message = "ERROR: Extraction failed (no files found after unzip). See console for details."
  end
else
  final_message = "ERROR: Download failed (file was not created). See console for details."
end

cleanup()
reaper.MB(final_message, "Update Toolbar Icons", 0)
