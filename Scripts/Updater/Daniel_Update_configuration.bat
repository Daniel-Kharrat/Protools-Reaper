@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM REAPER Configuration Update Helper
REM
REM Windows
REM
REM Argument:
REM   %1 = REAPER Resource Path
REM
REM Waits for REAPER to close, copies the files prepared by
REM Daniel_Update configuration.lua (Data\Daniel Kharrat\Update) into
REM the resource folder, then relaunches REAPER.
REM
REM This helper is separate from Daniel_Restore_ini_files.bat
REM and Daniel_Merge_keyboard_shortcuts.bat.
REM ============================================================

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

set "DATA_FOLDER=%RESOURCE_PATH%\Data"

set "DAN_FOLDER=%DATA_FOLDER%\Daniel Kharrat"

set "STAGE=%DAN_FOLDER%\Update"
set "EXTRACTED=%STAGE%\extracted"

set "INI_MERGED=%STAGE%\reaper.ini.merged"
set "INI_TARGET=%RESOURCE_PATH%\reaper.ini"

set "KB_MERGED=%STAGE%\reaper-kb.merged.ini"
set "KB_TARGET=%RESOURCE_PATH%\reaper-kb.ini"

set "VERSION_SOURCE=%STAGE%\applied_version.txt"
set "VERSION_TARGET=%DAN_FOLDER%\Config_Version.txt"

set "FAILED=0"

REM Log file (kept, so a failed update can be diagnosed) and the REAPER
REM executable as passed by the Lua script (used if it cannot be detected)
set "LOG=%DAN_FOLDER%\Update_Log.txt"
set "REAPER_EXE_ARG=%~2"

call :LOG "Helper started. Resource path: %RESOURCE_PATH%"

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
call :LOG "REAPER process not found - it has probably already closed."
echo REAPER process not found - it has probably already closed.
set "REAPER_EXECUTABLE=%REAPER_EXE_ARG%"
if "!REAPER_EXECUTABLE!"=="" (
echo ERROR: Could not find the running REAPER process.
call :LOG "ERROR: no REAPER process and no executable path was given."
exit /b 1
)
goto :REAPER_CLOSED
)

echo REAPER process found.
echo PID: %REAPER_PID%

REM ============================================================
REM GET REAPER EXECUTABLE PATH
REM ============================================================

for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-Process -Id %REAPER_PID% -ErrorAction SilentlyContinue).Path"`) do (
set "REAPER_EXECUTABLE=%%A"
)

if "%REAPER_EXECUTABLE%"=="" set "REAPER_EXECUTABLE=%REAPER_EXE_ARG%"

if "%REAPER_EXECUTABLE%"=="" (
echo ERROR: Could not determine the REAPER executable.
call :LOG "ERROR: could not determine the REAPER executable."
exit /b 1
)

echo Executable: %REAPER_EXECUTABLE%

REM ============================================================
REM WAIT FOR REAPER TO CLOSE
REM ============================================================

echo.
echo Waiting for REAPER to close...

:WAIT_FOR_REAPER

tasklist /FI "PID eq %REAPER_PID%" /NH 2>nul | findstr /R /C:"%REAPER_PID%" >nul

if not errorlevel 1 (
timeout /t 1 /nobreak >nul
goto :WAIT_FOR_REAPER
)

:REAPER_CLOSED

echo REAPER has completely closed.
call :LOG "REAPER has closed."

REM ============================================================
REM APPLY THE UPDATE
REM ============================================================

if not exist "%STAGE%" (
echo.
echo Nothing to apply - staging folder not found.
goto :AFTER_APPLY
)

REM ------------------------------------------------------------
REM Files that are replaced as they are
REM ------------------------------------------------------------

if exist "%EXTRACTED%" (
echo.
echo Copying configuration files...

robocopy "%EXTRACTED%" "%RESOURCE_PATH%" /E /NFL /NDL /NJH /NJS /NP >nul
call :LOG "robocopy finished with exit code !errorlevel!"

if errorlevel 8 (
echo ERROR: Failed to copy the configuration files.
set "FAILED=1"
) else (
echo Configuration files copied successfully.
)
)

REM ------------------------------------------------------------
REM reaper.ini - merged
REM ------------------------------------------------------------

if exist "%INI_MERGED%" (
echo.
echo Applying merged reaper.ini...

copy /Y "%INI_MERGED%" "%INI_TARGET%" >nul

if errorlevel 1 (
echo ERROR: Failed to apply merged reaper.ini.
set "FAILED=1"
) else (
echo reaper.ini updated successfully.
)
)

REM ------------------------------------------------------------
REM reaper-kb.ini - merged keyboard shortcuts
REM ------------------------------------------------------------

if exist "%KB_MERGED%" (
echo.
echo Applying merged keyboard shortcuts...

copy /Y "%KB_MERGED%" "%KB_TARGET%" >nul

if errorlevel 1 (
echo ERROR: Failed to apply merged keyboard shortcuts.
set "FAILED=1"
) else (
echo Keyboard shortcuts merged successfully.
)
)

REM ------------------------------------------------------------
REM Record the version and clean up
REM ------------------------------------------------------------

if "%FAILED%"=="0" (
copy /Y "%VERSION_SOURCE%" "%VERSION_TARGET%" >nul 2>&1
rmdir /s /q "%STAGE%"
) else (
echo.
echo Some files could not be applied. The prepared files were kept in the Data\Daniel Kharrat\Update folder.
)

:AFTER_APPLY

REM ============================================================
REM RELAUNCH REAPER
REM ============================================================

echo.
echo Launching REAPER...

call :LOG "Launching REAPER: %REAPER_EXECUTABLE% (failed=%FAILED%)"
start "" "%REAPER_EXECUTABLE%"

REM ============================================================
REM FINISHED
REM ============================================================

echo.
echo ============================================
if "%FAILED%"=="0" (
echo REAPER configuration update completed.
) else (
echo REAPER configuration update finished with errors.
)
echo ============================================

exit /b 0

REM ============================================================
REM LOG - appends a line with the time to the log file
REM ============================================================

:LOG
echo %date% %time% %* >>"%LOG%"
exit /b 0
