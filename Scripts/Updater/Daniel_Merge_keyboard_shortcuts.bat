@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM REAPER Keyboard Shortcuts Merge Helper
REM
REM Windows
REM
REM Argument:
REM   %1 = REAPER Resource Path
REM
REM Waits for REAPER to close, copies the merged keymap
REM (Data\Daniel Kharrat\reaper-kb.merged.ini, prepared by
REM Daniel_Merge keyboard shortcuts.lua) over reaper-kb.ini,
REM then relaunches REAPER.
REM
REM This helper is separate from Daniel_Restore_ini_files.bat
REM and does not touch any personal settings.
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

set "KB_MERGED=%DATA_FOLDER%\Daniel Kharrat\reaper-kb.merged.ini"
set "KB_TARGET=%RESOURCE_PATH%\reaper-kb.ini"

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

echo REAPER has completely closed.

REM ============================================================
REM APPLY MERGED KEYBOARD SHORTCUTS
REM ============================================================

if exist "%KB_MERGED%" (
echo.
echo Applying merged keyboard shortcuts...

copy /Y "%KB_MERGED%" "%KB_TARGET%" >nul

if errorlevel 1 (
echo ERROR: Failed to apply merged keyboard shortcuts.
) else (
del "%KB_MERGED%" >nul 2>&1
echo Keyboard shortcuts merged successfully.
)
) else (
echo.
echo reaper-kb.merged.ini not found - skipping.
)

REM ============================================================
REM RELAUNCH REAPER
REM ============================================================

echo.
echo Launching REAPER...

start "" "%REAPER_EXECUTABLE%"

REM ============================================================
REM FINISHED
REM ============================================================

echo.
echo ============================================
echo REAPER keyboard shortcuts merge completed.
echo ============================================

exit /b 0
