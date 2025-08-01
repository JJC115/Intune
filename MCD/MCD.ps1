<#
.SYNOPSIS
  Intune-deployable Magicard driver installer + diagnostics (relative path, MCD root).

.DESCRIPTION
  - Expects driver files directly in .\MCD (no extra nesting).
  - Logs to IntuneManagementExtension log subtree.
  - Sets LANGID to U.S. English.
  - Installs magu.inf via pnputil, with DISM fallback.
  - Verifies presence by name or enumeration.
  - Captures outputs for troubleshooting.
#>

# --- PATHS ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$base = Join-Path $scriptDir "MCD"
$inf = Join-Path $base "magu.inf"
$infBase = [IO.Path]::GetFileNameWithoutExtension($inf)

# --- LOGGING SETUP ---
$intuneLogDir = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\MagicardDriverInstall"
$logFile = Join-Path $intuneLogDir "install.log"

if (-not (Test-Path $intuneLogDir)) {
    New-Item -Path $intuneLogDir -ItemType Directory -Force | Out-Null
}

function Log {
    param($msg)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$ts  $msg" | Add-Content -Path $logFile
}

# Start log
"==== Magicard Driver Install Started: $(Get-Date) ====" | Out-File -FilePath $logFile -Encoding utf8

$driverSearchPattern = "Magicard"
$regPath = "HKLM:\SOFTWARE\Ultra Electronics Ltd\Ultra Installer\Ultra Driver\Support"

# --- VERIFICATION FUNCTION ---
function Test-Installed {
    $foundDriver = Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $driverSearchPattern }
    if ($foundDriver) {
        Log "Detected printer driver by name match: $($foundDriver.Name)"
        return $true
    }
    $enumText = pnputil /enum-drivers 2>&1 | Out-String
    if ($enumText -match $driverSearchPattern -or $enumText -match [regex]::Escape($infBase)) {
        Log "Detected driver package in pnputil enumeration matching pattern ('$driverSearchPattern' or '$infBase')."
        return $true
    }
    return $false
}

# --- MAIN ---
try {
    # Elevation
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Script is not running elevated."
    }
    Log "Elevation confirmed."

    # Validate INF presence
    if (-not (Test-Path $inf)) {
        throw "Cannot find magu.inf at expected path '$inf'. Ensure MCD folder is adjacent to the script and contains the INF."
    }
    Log "Found INF at $inf"

    # Signature for diagnostics
    try {
        $sig = Get-AuthenticodeSignature -FilePath $inf
        Log "Authenticode signature: Status=$($sig.Status); Message='$($sig.StatusMessage)'"
    } catch {
        Log "Failed to get signature of INF: $($_.Exception.Message)"
    }

    # Set LANGID to US English
    try {
        New-Item -Path $regPath -Force | Out-Null
        New-ItemProperty -Path $regPath -Name "LANGID" -PropertyType DWord -Value 0x409 -Force | Out-Null
        Log "Set registry LANGID to 0x0409 (U.S. English)."
    } catch {
        Log "Failed to set LANGID: $($_.Exception.Message)"
    }

    # Install via pnputil
    Log "Installing driver with pnputil."
    $pnputilOutput = pnputil /add-driver "$inf" /install 2>&1
    Log "pnputil output:`n$pnputilOutput"
    if ($LASTEXITCODE -ne 0) {
        Log "pnputil returned exit code $LASTEXITCODE."
    }

    Start-Sleep -Seconds 4

    # Enumerate current state
    Log "Enumerating installed driver packages."
    pnputil /enum-drivers 2>&1 | ForEach-Object { Log $_ }

    Log "Listing installed printer drivers."
    try {
        Get-PrinterDriver -ErrorAction SilentlyContinue | Format-Table Name,Manufacturer | Out-String | ForEach-Object { Log $_ }
    } catch {
        Log "Failed to list printer drivers: $($_.Exception.Message)"
    }

    # Verification
    $installed = Test-Installed

    if (-not $installed) {
        Log "Primary verification failed; attempting DISM fallback."
        $dismOutput = dism /online /Add-Driver /Driver:"$inf" /ForceUnsigned 2>&1
        Log "DISM output:`n$dismOutput"
        Start-Sleep -Seconds 3

        Log "Re-enumerating after DISM."
        pnputil /enum-drivers 2>&1 | ForEach-Object { Log $_ }
        try {
            Get-PrinterDriver -ErrorAction SilentlyContinue | Format-Table Name,Manufacturer | Out-String | ForEach-Object { Log $_ }
        } catch {
            Log "Failed to list printer drivers post-DISM: $($_.Exception.Message)"
        }

        $installed = Test-Installed
    }

    if ($installed) {
        Log "Installation verified."
        Write-Output "SUCCESS"
        exit 0
    } else {
        throw "Verification failed: no Magicard driver detected after all attempts."
    }
}
catch {
    $err = $_.Exception.Message
    Log "ERROR: $err"
    Write-Error "Installation failed: $err"
    Write-Output "FAIL: $err"
    exit 1
}
