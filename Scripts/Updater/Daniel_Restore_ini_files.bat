@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM REAPER Restore Helper
REM
REM Windows
REM
REM Arguments:
REM   %1 = REAPER Resource Path
REM   %2 = REAPER executable (used if it cannot be detected)
REM
REM Waits for REAPER to close, copies the files prepared by
REM Daniel_Restore personal settings.lua
REM (Data\Daniel Kharrat\Restore\files) into the resource
REM folder, then relaunches REAPER.
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

set "STAGE=%DAN_FOLDER%\Restore"
set "STAGED_FILES=%STAGE%\files"

set "FAILED=0"

REM The REAPER executable as passed by the Lua script (used if it cannot
REM be detected)
set "REAPER_EXE_ARG=%~2"

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
echo REAPER process not found - it has probably already closed.
set "REAPER_EXECUTABLE=%REAPER_EXE_ARG%"
if "!REAPER_EXECUTABLE!"=="" (
echo ERROR: Could not find the running REAPER process.
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

REM ============================================================
REM RESTORE THE FILES
REM ============================================================

if not exist "%STAGED_FILES%" (
echo.
echo Nothing to restore - the prepared files were not found.
goto :AFTER_RESTORE
)

echo.
echo Restoring files...

robocopy "%STAGED_FILES%" "%RESOURCE_PATH%" /E /NFL /NDL /NJH /NJS /NP >nul

if errorlevel 8 (
echo ERROR: Failed to restore the files.
set "FAILED=1"
) else (
echo Files restored successfully.
)

if "%FAILED%"=="0" (
rmdir /s /q "%STAGE%"
) else (
echo.
echo Some files could not be restored. The prepared files were kept in the Data\Daniel Kharrat\Restore folder.
)

:AFTER_RESTORE

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
if "%FAILED%"=="0" (
echo REAPER restore completed.
) else (
echo REAPER restore finished with errors.
)
echo ============================================

exit /b 0
