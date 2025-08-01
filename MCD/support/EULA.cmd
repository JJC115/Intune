@echo off
@rem ---------------------------------------------------------------------------
@rem Copyright (C) 2024 Magicard Ltd. All rights reserved.
@rem ---------------------------------------------------------------------------
@rem Shows the EULA dialog to allow the user to accept or decline the EULA.
@rem ---------------------------------------------------------------------------

setlocal

@rem ---------------------------------------------------------------------------
@rem Work out what program to run.
@rem ---------------------------------------------------------------------------
set status-x64=%WINDIR%\system32\spool\drivers\x64\3\status.exe
set status-x86=%WINDIR%\system32\spool\drivers\w32x86\3\status.exe
set status-exe=

if exist %status-x64% (
  set status-exe=%status-x64%
  goto RUN_STATUS
)

if exist %status-x86% (
  set status-exe=%status-x86%
  RUN_STATUS
)

@echo ---------------------------------------------------------------------------
@echo Error, cannot find Status Utility program, please contact support for
@echo more assistance.
@echo ---------------------------------------------------------------------------
goto END

@rem ---------------------------------------------------------------------------
@rem Show the EULA acceptance dialog.
@rem ---------------------------------------------------------------------------
:RUN_STATUS
start %status-exe% -show-eula-dialog-force

:END
endlocal
