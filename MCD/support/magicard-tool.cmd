@echo off
@rem ---------------------------------------------------------------------------
@rem Copyright (C) 2024 Magicard Ltd. All rights reserved.
@rem ---------------------------------------------------------------------------
@rem Gathers support information
@rem ---------------------------------------------------------------------------

setlocal

set verbose=%1

@rem Set the filename prefix
set prefix=magicard-support

@rem ---------------------------------------------------------------------------
@rem Make sure the target folder exists
@rem ---------------------------------------------------------------------------
set folder=%programdata%\Magicard Ltd\support
if not exist "%folder%" (
    echo Creating folder "%folder%
    mkdir "%folder%"
) else (
    echo Folder "%folder%" exists ...
)

if not exist "%folder%" (
    echo Error: could not create the folder "%folder%", exiting
    pause
    goto end
)

@echo on

@rem Delete the files that may be there already.
@echo.
@echo off
set file="%folder%\%prefix%*.txt"
if exist %file% (
    del "%folder%\%prefix%*.txt" /q
)
@echo on

@rem ---------------------------------------------------------------------------
@rem Gather the data and create the files.
@rem ---------------------------------------------------------------------------
@echo.
@echo off
set program=magicard-support.exe
if not exist %program% (
    echo Error: The program '%program%' does not exist, exiting.
    goto end
)
@echo on
%program% -output "%folder%\%prefix%.txt"
@echo.
REG EXPORT "HKLM\SOFTWARE\Magicard Ltd." "%folder%\%prefix%-hklm-magicard-ltd.txt" /y
@echo.
REG EXPORT "HKCU\SOFTWARE\Magicard Ltd." "%folder%\%prefix%-hkcu-magicard-ltd.txt" /y
@echo.
REG EXPORT "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Printers" "%folder%\%prefix%-hklm-printers.txt" /y
@echo.
REG QUERY "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v "PendingFileRenameOperations" > "%folder%\%prefix%-PendingFileRenameOperations.txt"
@echo off
if "%ERRORLEVEL%" NEQ "0" (
    echo 'PendingFileRenameOperations' key was not found > "%folder%\%prefix%-PendingFileRenameOperations.txt"
)
@echo on


@echo off
@rem ---------------------------------------------------------------------------
@rem Gathering pnp information.
@rem ---------------------------------------------------------------------------
@echo.
@echo Gathering pnp information.
setlocal EnableDelayedExpansion

set pnpfile="%folder%\%prefix%-pnp-list.txt"
echo Magicard pnp files: > %pnpfile%

set GetVersion=FALSE

set Manufacturer="Ultra Electronics Card Systems Ltd." "Magicard Ltd."

for %%M in (%Manufacturer%) do (
    for /F "tokens=1-2 delims=:" %%a in ('pnputil -e') do (
        for /F "tokens=*" %%b in ("%%b") do (
            if "%%b" equ %%M (
                echo !line1prior! >> %pnpfile%
                echo !line1prior!
                set GetVersion=TRUE
            ) else (
                set "line1prior=%%a: %%b"
                if !GetVersion! equ TRUE (
                    if "%%a" equ "Driver date and version " (
                       echo %%a: %%b >> %pnpfile%
                       echo %%a: %%b
                       set GetVersion=FALSE
                    )
                )
            )
        )
    )
)

echo.

endlocal
@echo on


@echo off
@rem ---------------------------------------------------------------------------
@rem Copy the logs to the support folder.
@rem ---------------------------------------------------------------------------
set source-folder=%programdata%\Magicard Ltd\logs
set target-folder=%folder%\logs

@echo Gathering log files ...
if /I [%verbose%]==[-v] (
    @echo source-folder = [%source-folder%]
    @echo target-folder = [%target-folder%]
    @echo.
)

if exist "%target-folder%" (
    rmdir "%target-folder%" /s /q
)

mkdir "%target-folder%"

for %%f in (log timings driverevent) do (
    copy "%source-folder%\%%f-*.txt" "%target-folder%" > NUL:
)
@echo on


@echo off
@rem ---------------------------------------------------------------------------
@rem Copy the usage data collection files to the support folder. These files may
@rem not exist and they are only created if a registry setting is set.
@rem ---------------------------------------------------------------------------
set source-folder=%temp%\magicard-temp
set target-folder=%folder%\usage-data

@echo Gathering usage files ...
if /I [%verbose%]==[-v] (
    @echo source-folder = [%source-folder%]
    @echo target-folder = [%target-folder%]
    @echo.
)

if exist "%target-folder%" (
    rmdir "%target-folder%" /s /q
)

mkdir "%target-folder%"

for %%f in (cd el fl ph pu sp ud) do (
    copy "%source-folder%\%%f~*.tmp" "%target-folder%" > NUL:
)
@echo on


@echo off
@rem ---------------------------------------------------------------------------
@rem Copy files named setupapi*.log from %WINDIR%\INF the support folder.
@rem ---------------------------------------------------------------------------
set source-folder=%WINDIR%\INF
set target-folder=%folder%\setupapi

@echo Gathering Windows setupapi log files ...
if /I [%verbose%]==[-v] (
    @echo source-folder = [%source-folder%]
    @echo target-folder = [%target-folder%]
    @echo.
)

if exist "%target-folder%" (
    rmdir "%target-folder%" /s /q
)

mkdir "%target-folder%"

copy "%source-folder%\setupapi*.log" "%target-folder%" > NUL:
@echo on


@echo off
@rem ---------------------------------------------------------------------------
@rem Copy files named %WINDIR\Logs\WindowsUpdate\*.* to the support folder.
@rem ---------------------------------------------------------------------------
set source-folder=%WINDIR%\Logs\WindowsUpdate
set target-folder=%folder%\windowsupdate

@echo Gathering Windows Update log files ...
if /I [%verbose%]==[-v] (
    @echo source-folder = [%source-folder%]
    @echo target-folder = [%target-folder%]
    @echo.
)

if exist "%target-folder%" (
    rmdir "%target-folder%" /s /q
)

mkdir "%target-folder%"

copy "%source-folder%\*.*" "%target-folder%" > NUL:
@echo on


@echo off
@rem ---------------------------------------------------------------------------
@rem Execute systeminfo.exe and save the output to the support folder.
@rem ---------------------------------------------------------------------------
set program=%WINDIR%\system32\systeminfo.exe
set target=%folder%\%prefix%-systeminfo.txt

@echo Gathering system info ...
if /I [%verbose%]==[-v] (
    @echo program = [%program%]
    @echo target  = [%target%]
    @echo.
)

"%program%" > "%target%"

@echo on


@echo off
@rem ---------------------------------------------------------------------------
@rem Create a date/time string that will be used for the ZIP file.
@rem
@rem   yyy-mm-ddThh-mm-ss
@rem ---------------------------------------------------------------------------
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /format:list') do (
    set datetime=%%I
)

@rem Extract the various portions of the date and time
set yyyy=%datetime:~0,4%
set mmm=%datetime:~4,2%
set dd=%datetime:~6,2%
set hh=%datetime:~8,2%
set mm=%datetime:~10,2%
set ss=%datetime:~12,2%

@rem Create the filenames
set base-zip-filename=magicard-support
set dated-zip-filename=%base-zip-filename%-%yyyy%-%mmm%-%dd%T%hh%-%mm%-%ss%.zip
set zip-filename=%base-zip-filename%.zip

pushd %folder%

@rem ---------------------------------------------------------------------------
@rem Create the ZIP file
@rem ---------------------------------------------------------------------------
tar -c -a -f "%dated-zip-filename%" "*.txt" "logs\*.txt" "setupapi\*.*" "windowsupdate\*.*" "usage-data\*.*"

@rem Copy the dated file created above to the standard filename
copy "%dated-zip-filename%" "%zip-filename%" /Y > NUL:

popd
@echo on


@echo off
@echo.
@echo ---------------------------------------------------------------------------
@echo  Files created in folder "%folder%"
@echo ---------------------------------------------------------------------------
dir "%folder%\%prefix%*.txt" /b
dir "%folder%\%zip-filename%" /b
dir "%folder%\%dated-zip-filename%" /b
@echo.

pause

@rem Show the folder to the user
explorer.exe "%folder%"

:end
endlocal
