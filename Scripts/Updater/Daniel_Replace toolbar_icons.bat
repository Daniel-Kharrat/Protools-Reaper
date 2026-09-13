@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM REAPER Toolbar Icons Updater
REM
REM Windows
REM
REM Argument:
REM   %1 = REAPER Resource Path
REM
REM Process:
REM 1. Find running REAPER process
REM 2. Get REAPER executable path
REM 3. Wait for REAPER to close
REM 4. Download toolbar_icons.zip
REM 5. Extract into temporary toolbar_icons folder
REM 6. Verify extracted contents
REM 7. Replace Data\toolbar_icons completely
REM 8. Verify replacement
REM 9. Clean up
REM 10. Relaunch REAPER
REM ============================================================

REM ============================================================
REM CONFIGURATION
REM ============================================================

set "DOWNLOAD_URL=https://github.com/Daniel-Kharrat/Protools-Reaper/raw/refs/heads/master/MISC%%20Data/toolbar_icons.zip"

REM ============================================================
REM REAPER RESOURCE PATH
REM ============================================================

set "RESOURCE_PATH=%~1"

if "%RESOURCE_PATH%"=="" (
echo ERROR: REAPER resource path was not provided.
exit /b 1
)

REM ============================================================
REM PATHS
REM ============================================================

set "TARGET_PARENT=%RESOURCE_PATH%\Data"
set "TARGET_DIR=%RESOURCE_PATH%\Data\toolbar_icons"

set "WORK_DIR=%RESOURCE_PATH%.toolbar_icons_update_%RANDOM%%RANDOM%"
set "ZIP_PATH=%WORK_DIR%\toolbar_icons.zip"
set "NEW_TOOLBAR_DIR=%WORK_DIR%\toolbar_icons"

set "BACKUP_DIR=%TARGET_PARENT%.toolbar_icons_old"

REM ============================================================
REM CHECK REAPER DATA DIRECTORY
REM ============================================================

if not exist "%TARGET_PARENT%" (
echo ERROR: REAPER Data directory does not exist:
echo %TARGET_PARENT%
exit /b 1
)

REM ============================================================
REM DETERMINE REAPER PROCESS
REM ============================================================

set "REAPER_PID="
set "REAPER_EXECUTABLE="

REM ============================================================
REM FIND RUNNING REAPER PROCESS
REM ============================================================

for /f "tokens=2 delims=," %%A in ('tasklist /FI "IMAGENAME eq reaper.exe" /FO CSV /NH 2^>nul') do (
set "REAPER_PID=%%~A"
goto :FOUND_REAPER
)

:FOUND_REAPER

if "%REAPER_PID%"=="" (
echo ERROR: Could not find the running REAPER process.
exit /b 1
)

echo REAPER process found.
echo PID: %REAPER_PID%

REM ============================================================
REM GET REAPER EXECUTABLE PATH
REM ============================================================

for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-Process -Id %REAPER_PID% -ErrorAction SilentlyContinue).Path"`) do (
set "REAPER_EXECUTABLE=%%A"
)

if "%REAPER_EXECUTABLE%"=="" (
echo ERROR: Could not determine the REAPER executable.
exit /b 1
)

echo Executable: %REAPER_EXECUTABLE%

REM ============================================================
REM CREATE TEMPORARY WORKING DIRECTORY
REM ============================================================

mkdir "%WORK_DIR%" >nul 2>&1

if not exist "%WORK_DIR%" (
echo ERROR: Could not create temporary working directory.
exit /b 1
)

REM ============================================================
REM WAIT FOR REAPER TO CLOSE
REM ============================================================

echo.
echo Waiting for REAPER to close...

REM Give the REAPER close command a moment to take effect.

timeout /t 1 /nobreak >nul

:WAIT_FOR_REAPER

tasklist /FI "PID eq %REAPER_PID%" /NH 2>nul | findstr /R /C:"%REAPER_PID%" >nul

if not errorlevel 1 (
timeout /t 1 /nobreak >nul
goto :WAIT_FOR_REAPER
)

echo REAPER has completely closed.

REM ============================================================
REM DOWNLOAD
REM ============================================================

echo.
echo Downloading toolbar icons...

curl.exe -L --fail --progress-bar --show-error -o "%ZIP_PATH%" "%DOWNLOAD_URL%"

if errorlevel 1 (
echo ERROR: Toolbar icon download failed.
goto :FAILED
)

REM ============================================================
REM VERIFY ZIP EXISTS
REM ============================================================

if not exist "%ZIP_PATH%" (
echo ERROR: Downloaded ZIP is missing.
goto :FAILED
)

for %%A in ("%ZIP_PATH%") do (
if %%~zA LEQ 0 (
echo ERROR: Downloaded ZIP is empty.
goto :FAILED
)
)

echo.
echo Download successful.

REM ============================================================
REM CREATE NEW TOOLBAR_ICONS DIRECTORY
REM ============================================================

mkdir "%NEW_TOOLBAR_DIR%" >nul 2>&1

if not exist "%NEW_TOOLBAR_DIR%" (
echo ERROR: Could not create temporary toolbar_icons directory.
goto :FAILED
)

REM ============================================================
REM EXTRACT ZIP
REM ============================================================

echo.
echo Extracting toolbar icons...

powershell -NoProfile -Command "Expand-Archive -LiteralPath '%ZIP_PATH%' -DestinationPath '%NEW_TOOLBAR_DIR%' -Force"

if errorlevel 1 (
echo ERROR: ZIP extraction failed.
goto :FAILED
)

echo Extraction successful.

REM ============================================================
REM VERIFY EXTRACTED TOOLBAR ICONS
REM ============================================================

set "PNG_COUNT=0"

for /r "%NEW_TOOLBAR_DIR%" %%F in (*.png) do (
set /a PNG_COUNT+=1
)

if "%PNG_COUNT%"=="0" (
echo ERROR: No PNG files were found after extraction.
goto :FAILED
)

if not exist "%NEW_TOOLBAR_DIR%\150" (
echo ERROR: Extracted folder is missing the 150 directory.
goto :FAILED
)

if not exist "%NEW_TOOLBAR_DIR%\200" (
echo ERROR: Extracted folder is missing the 200 directory.
goto :FAILED
)

echo Verification successful.
echo PNG files found: %PNG_COUNT%
echo 150 directory found.
echo 200 directory found.

REM ============================================================
REM REPLACE EXISTING TOOLBAR_ICONS FOLDER
REM ============================================================

echo.
echo Replacing existing toolbar_icons folder...

if exist "%BACKUP_DIR%" (
rmdir /s /q "%BACKUP_DIR%"
)

if exist "%TARGET_DIR%" (
move "%TARGET_DIR%" "%BACKUP_DIR%" >nul

if errorlevel 1 (
echo ERROR: Could not move the existing toolbar_icons folder.
goto :FAILED
)
)

move "%NEW_TOOLBAR_DIR%" "%TARGET_DIR%" >nul

if errorlevel 1 (
echo ERROR: Could not move the new toolbar_icons folder into place.

if exist "%BACKUP_DIR%" (
move "%BACKUP_DIR%" "%TARGET_DIR%" >nul
)

goto :FAILED
)

REM ============================================================
REM VERIFY REPLACEMENT
REM ============================================================

echo.
echo Verifying new toolbar_icons folder...

if not exist "%TARGET_DIR%" (
echo ERROR: New toolbar_icons folder does not exist.
goto :FAILED
)

set "PNG_COUNT_AFTER=0"

for /r "%TARGET_DIR%" %%F in (*.png) do (
set /a PNG_COUNT_AFTER+=1
)

if "%PNG_COUNT_AFTER%"=="0" (
echo ERROR: No PNG files found in the replaced folder.
goto :FAILED
)

if not exist "%TARGET_DIR%\150" (
echo ERROR: New toolbar_icons folder is missing 150.
goto :FAILED
)

if not exist "%TARGET_DIR%\200" (
echo ERROR: New toolbar_icons folder is missing 200.
goto :FAILED
)

echo Replacement successful.
echo PNG files now installed: %PNG_COUNT_AFTER%

REM ============================================================
REM REMOVE OLD BACKUP
REM ============================================================

if exist "%BACKUP_DIR%" (
rmdir /s /q "%BACKUP_DIR%"
)

REM ============================================================
REM CLEAN UP
REM ============================================================

if exist "%WORK_DIR%" (
rmdir /s /q "%WORK_DIR%"
)

REM ============================================================
REM RELAUNCH REAPER
REM ============================================================

echo.
echo Launching REAPER...

start "" "%REAPER_EXECUTABLE%"

timeout /t 2 /nobreak >nul

tasklist /FI "IMAGENAME eq reaper.exe" /NH 2>nul | findstr /I /C:"reaper.exe" >nul

if errorlevel 1 (
echo ERROR: REAPER did not start.
exit /b 1
)

echo REAPER started successfully.

echo.
echo ============================================
echo Toolbar icons updated successfully.
echo ============================================

exit /b 0

REM ============================================================
REM FAILURE CLEANUP
REM ============================================================

:FAILED

echo.
echo ============================================
echo Toolbar icon updater failed.
echo ============================================

if exist "%WORK_DIR%" (
rmdir /s /q "%WORK_DIR%"
)

exit /b 1
