# PowerShell script to silently install HPDInstall.exe
# Logs written to %TEMP%\Intune\HPDInstall.log using Out-File
$ErrorActionPreference = 'Stop'

# Determine script directory
$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# Ensure Intune log directory exists
$logDir = Join-Path $env:TEMP 'Intune'
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Set log file
$log = Join-Path $logDir 'HPDInstall.log'
# Initialize log
"" | Out-File -FilePath $log

# Logging function
function Log {
    param($Message)
    $time = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$time $Message" | Out-File -FilePath $log -Append
}

Log "=== Starting HPDInstall.exe installation ==="

# Path to installer
$installer = Join-Path $ScriptRoot 'HPDInstall.exe'
Log "Looking for installer at $installer"

# Pattern for driver detection
$pattern = 'HP Smart Universal Printing (V3) (v2.07.1*'

# Detect specific driver before installation
$existing = Get-CimInstance -ClassName Win32_PrinterDriver |
    Where-Object { $_.Name -like $pattern }
if ($existing) {
    Log "Driver already installed: $($existing.Name)"
    exit 0
}


Log "Running installer..."

# Register any INF driver files into the DriverStore
$infFiles = Get-ChildItem -Path $ScriptRoot -Filter '*.inf' -Recurse
foreach ($inf in $infFiles) {
    Log "Registering driver INF: $($inf.FullName)"
    Start-Process -FilePath pnputil.exe -ArgumentList "/add-driver `"$($inf.FullName)`" /install" -Wait -NoNewWindow
}

Start-Process -FilePath $installer -ArgumentList '/S' -Wait -NoNewWindow

# Wait briefly for driver registration to complete
Start-Sleep -Seconds 5

Log "Installation finished, verifying..."
$installed = Get-CimInstance -ClassName Win32_PrinterDriver |
    Where-Object { $_.Name -like $pattern }
if ($installed) {
    Log "SUCCESS: Driver installed: $($installed.Name)"
    exit 0
} else {
    Log "ERROR: Driver verification failed. Dumping all HP drivers for debugging:"
    Get-CimInstance -ClassName Win32_PrinterDriver |
        Where-Object { $_.Name -like '*HP*' } |
        ForEach-Object { Log " - $($_.Name)" }
    exit 1
}