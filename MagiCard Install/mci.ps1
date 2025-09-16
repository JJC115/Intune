<#
.SYNOPSIS
    Installs the Magicard drivers from the Intune unpack folder, with logging and retry/fallback logic.
.DESCRIPTION
    1. Forces ExecutionPolicy Bypass in this process.
    2. Assumes you’re already running from the root of the unpacked Intune folder.
    3. Checks for Administrator rights.
    4. Recursively finds all .inf files under .\Magicard\v3.1.2.1095 and installs them.
    5. Retries each install up to 3 times, with a 5-second delay, then falls back to DISM if pnputil fails.
    6. Verifies driver presence after install.
    7. Logs everything to %TEMP%\Intune\MagicardInstall_YYYYMMDD_HHMMSS.log.
#>

[CmdletBinding()]
param()

# 1) Bypass any execution‐policy restrictions for this session
Set-ExecutionPolicy Bypass -Scope Process -Force

# --- Log Setup ---
$LogFolder = Join-Path $env:TEMP 'Intune'
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile   = Join-Path $LogFolder "MagicardInstall_$timestamp.log"
"$timestamp [INFO] Starting Magicard driver installation" | Out-File $LogFile -Encoding utf8

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $time  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "$time [$Level]  $Message"
    switch ($Level) {
        'ERROR' { Write-Error $Message; break }
        'WARN'  { Write-Warning $Message; break }
        default { Write-Host $entry; break }
    }
    $entry | Out-File -FilePath $LogFile -Append -Encoding utf8
}

# Stop on uncaught errors
$ErrorActionPreference = 'Stop'

# --- Retry Helper (from HPDInstall.ps1) ---
function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)] [ScriptBlock] $ScriptBlock,
        [int] $MaxAttempts = 3,
        [int] $DelaySeconds = 5
    )
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            & $ScriptBlock
            return $true
        } catch {
            if ($i -lt $MaxAttempts) {
                Write-Log "Attempt $i failed: $_. Retrying in $DelaySeconds sec..." -Level WARN
                Start-Sleep -Seconds $DelaySeconds
            } else {
                Write-Log "All $MaxAttempts attempts failed." -Level ERROR
                return $false
            }
        }
    }
}

function Assert-Admin {
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
                    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        if (-not $isAdmin) {
            Write-Log "This script must be run as Administrator." -Level ERROR
            exit 1
        }
        Write-Log "Confirmed running as Administrator."
    } catch {
        Write-Log "Error checking admin rights: $_" -Level ERROR
        exit 1
    }
}

function Install-MagicardDrivers {
    # direct relative path as requested
    $DriverFolder = '.\Magicard\v3.1.2.1095'

    if (-not (Test-Path $DriverFolder -PathType Container)) {
        Write-Log "Driver folder not found: $DriverFolder" -Level ERROR
        exit 1
    }
    Write-Log "Found driver folder: $DriverFolder"

    $infFiles = Get-ChildItem -Path $DriverFolder -Filter '*.inf' -Recurse
    if (-not $infFiles) {
        Write-Log "No .inf files found under $DriverFolder" -Level WARN
        return
    }
    Write-Log "Found $($infFiles.Count) .inf file(s) to install."

    foreach ($inf in $infFiles) {
        $infPath = $inf.FullName
        Write-Log "Processing driver: $infPath"

        # 1) Try pnputil with retries
        $pnputilSuccess = Invoke-WithRetry -ScriptBlock {
            pnputil.exe /add-driver "`"$infPath`"" /install /force | Out-Null
        }

        if (-not $pnputilSuccess) {
            # 2) Fallback to DISM
            Write-Log "Falling back to DISM for $($inf.Name)" -Level WARN
            try {
                dism.exe /Online /Add-Driver /Driver:"$infPath" /ForceUnsigned /Quiet
                Write-Log "DISM install succeeded for $($inf.Name)"
            } catch {
                Write-Log "DISM install FAILED for $($inf.Name): $_" -Level ERROR
                continue
            }
        } else {
            Write-Log "pnputil succeeded for $($inf.Name)"
        }

        # 3) Verify driver in store
        $driverName = [IO.Path]::GetFileNameWithoutExtension($inf.Name)
        $enum = pnputil.exe /enum-drivers | Select-String -Pattern $driverName
        if ($enum) {
            Write-Log "Verified driver present: $driverName"
        } else {
            Write-Log "Could not verify driver in store: $driverName" -Level WARN
        }
    }

    Write-Log "Magicard driver installation complete."
}

# === MAIN ===
Write-Log "Script started."
Assert-Admin
Install-MagicardDrivers
Write-Log "Script finished successfully."
exit 0