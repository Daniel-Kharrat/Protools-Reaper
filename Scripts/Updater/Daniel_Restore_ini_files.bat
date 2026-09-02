@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM REAPER File Restore Helper
REM
REM Windows
REM
REM Argument:
REM   %1 = REAPER Resource Path
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

set "PERSONAL_SETTINGS=%RESOURCE_PATH%\Personal Settings"

set "SWS_SOURCE=%PERSONAL_SETTINGS%\sws-autocoloricon.ini"
set "SWS_TARGET=%RESOURCE_PATH%\sws-autocoloricon.ini"

set "SCREENSETS_SOURCE=%PERSONAL_SETTINGS%\reaper-screensets.ini"
set "SCREENSETS_TARGET=%RESOURCE_PATH%\reaper-screensets.ini"

REM ============================================================
REM CHECK SOURCE FILES
REM ============================================================

if not exist "%SWS_SOURCE%" (
echo ERROR: File not found:
echo %SWS_SOURCE%
exit /b 1
)

if not exist "%SCREENSETS_SOURCE%" (
echo ERROR: File not found:
echo %SCREENSETS_SOURCE%
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
REM RESTORE SWS AUTO COLOR / ICON
REM ============================================================

echo.
echo Restoring sws-autocoloricon.ini...

copy /Y "%SWS_SOURCE%" "%SWS_TARGET%" >nul

if errorlevel 1 (
echo ERROR: Failed to restore sws-autocoloricon.ini.
exit /b 1
)

echo SWS auto color restored successfully.

REM ============================================================
REM RESTORE REAPER SCREENSETS
REM ============================================================

echo.
echo Restoring reaper-screensets.ini...

copy /Y "%SCREENSETS_SOURCE%" "%SCREENSETS_TARGET%" >nul

if errorlevel 1 (
echo ERROR: Failed to restore reaper-screensets.ini.
exit /b 1
)

echo REAPER screensets restored successfully.

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
echo REAPER file restore completed successfully.
echo ============================================

exit /b 0
