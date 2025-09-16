@echo off&color e
setlocal EnableDelayedExpansion

net stop spooler
net start spooler

Echo.&Echo.

for /F "tokens=2 delims=:" %%a in ('pnputil -e') do for /F "tokens=*" %%b in ("%%a") do (
   if "%%b" equ "Ultra Electronics Card Systems Ltd." (
       	echo pnputil -f -d !line1prior!
	pnputil -f -d !line1prior!
   ) else (
      set "line1prior=%%b"
   )
)

for /F "tokens=2 delims=:" %%c in ('pnputil -e') do for /F "tokens=*" %%d in ("%%c") do (
   if "%%d" equ "Magicard Ltd." (	  
	  echo pnputil -f -d !line1prior!
	pnputil -f -d !line1prior!
   ) else (
      set "line1prior=%%d"
   )
)

Echo.&Echo.
REM echo == Press button to exit ==&pause>nul
exit