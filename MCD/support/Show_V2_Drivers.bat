@echo off&color e
setlocal EnableDelayedExpansion

echo == v2 Driver(s) Currently Installed ==
Echo.&Echo.

for /F "tokens=2 delims=:" %%a in ('pnputil -e') do for /F "tokens=*" %%b in ("%%a") do (
   if "%%b" equ "Magicard Ltd." (
      echo !line1prior!
   ) else (
      set "line1prior=%%b"
   )
)


Echo.&Echo.
echo == Press button to exit ==&pause>nul
exit