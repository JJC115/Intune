# ==========================================
# Intune Printer Installer Script with Failovers & Enhanced Logging (Updated Driver Verification)
# ==========================================
# This script:
#   • Installs the printer driver via pnputil.exe with retry logic and captures output
#   • Verifies the driver installation (by checking both INF and Driver Name)
#   • Creates the printer port if it doesn’t exist (with retries)
#   • Removes any existing instance of the printer (with retries)
#   • Creates the printer instance using Add-Printer (with retries)
#   • Logs every step to a network share log file
#
# Note: This script uses Sysnative if running as a 32-bit process on a 64-bit OS.
# ==========================================

# Set strict error handling
$ErrorActionPreference = "Stop"

# --- Key Variables (customize as needed) ---
$DriverFile    = "HPOneDriver.4081_V3_x64.inf"                # INF file name
$DriverModel   = "HP Smart Universal Printing (V3) (v2.07.1)"  # Expected driver model name (from INF)
$PrinterName   = "Admin Printer"                               # Desired printer display name
$PortName      = "IP_10.10.3.210"                              # Printer port name (using the IP)
$PortAddress   = "10.10.3.210"                                 # Port address

# --- Determine Computer Name and log file path on network share ---
$ComputerName = $env:COMPUTERNAME
$LogFile = "c:\logs\PrinterInstall_${ComputerName}.log"

# --- Determine Script Root ---
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $ScriptRoot = $PSScriptRoot
} else {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# --- Compute full path to the driver INF file ---
$DriverPath = Join-Path -Path $ScriptRoot -ChildPath $DriverFile

# -------------------------------
# Initialize Logging
# -------------------------------
if (Test-Path $LogFile) { Remove-Item $LogFile -Force }
New-Item -Path $LogFile -ItemType File -Force | Out-Null

function Write-Log {
    param (
        [string]$Message
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timeStamp - $Message"
    Add-Content -Path $LogFile -Value $entry
    Write-Output $entry
}

Write-Log "=== Starting Printer Installation on ${ComputerName} ==="
Write-Log "Script folder: ${ScriptRoot}"
Write-Log "Driver file path: ${DriverPath}"

# -------------------------------
# Retry Function
# -------------------------------
function Retry-Operation {
    param(
        [ScriptBlock]$Operation,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 5,
        [string]$OperationName = "Operation"
    )

    $attempt = 1
    while ($attempt -le $MaxAttempts) {
        try {
            Write-Log "${OperationName}: Attempt ${attempt}..."
            & $Operation
            return $true
        } catch {
            Write-Log "ERROR: ${OperationName} failed on attempt ${attempt}: $_"
            if ($attempt -lt $MaxAttempts) {
                Write-Log "${OperationName}: Retrying in ${DelaySeconds} seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
        }
        $attempt++
    }
    return $false
}

# -------------------------------
# Verify Driver File Exists
# -------------------------------
if (-not (Test-Path $DriverPath)) {
    Write-Log "ERROR: Driver file not found at ${DriverPath}. Exiting."
    exit 1
}

# -------------------------------
# Determine Correct pnputil.exe Path
# -------------------------------
# When running as a 32-bit process on a 64-bit OS, use Sysnative to access the 64-bit pnputil.exe
if (($env:PROCESSOR_ARCHITECTURE -eq "x86") -and (Test-Path "$env:windir\sysnative\pnputil.exe")) {
    $PnPUtilPath = "$env:windir\sysnative\pnputil.exe"
} else {
    $PnPUtilPath = "$env:windir\system32\pnputil.exe"
}

if (-not (Test-Path $PnPUtilPath)) {
    Write-Log "ERROR: pnputil.exe not found at ${PnPUtilPath}. Exiting."
    exit 1
}

# -------------------------------
# Install Printer Driver using pnputil.exe with Retry and Output Capture
# -------------------------------
$stdOutFile = Join-Path -Path $ScriptRoot -ChildPath "pnputil_output.txt"
$stdErrFile = Join-Path -Path $ScriptRoot -ChildPath "pnputil_error.txt"

$pnputilArgs = "/add-driver `"$DriverPath`" /install"
$installDriverOperation = {
    # Remove previous output files if present
    if (Test-Path $stdOutFile) { Remove-Item $stdOutFile -Force }
    if (Test-Path $stdErrFile) { Remove-Item $stdErrFile -Force }

    $process = Start-Process -FilePath $PnPUtilPath -ArgumentList $pnputilArgs -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $stdOutFile -RedirectStandardError $stdErrFile
    if ($process.ExitCode -ne 0) {
        throw "pnputil.exe returned exit code $($process.ExitCode)"
    }
}
if (-not (Retry-Operation -Operation $installDriverOperation -OperationName "Printer driver installation")) {
    Write-Log "ERROR: Printer driver installation failed after multiple attempts. Exiting."
    Write-Log "pnputil standard output:"
    if (Test-Path $stdOutFile) { Get-Content $stdOutFile | ForEach-Object { Write-Log "$_" } }
    Write-Log "pnputil standard error:"
    if (Test-Path $stdErrFile) { Get-Content $stdErrFile | ForEach-Object { Write-Log "$_" } }
    exit 1
}
Start-Sleep -Seconds 5  # Allow time for driver registration

# -------------------------------
# Verify Driver Installation (retry verification up to 3 times)
# -------------------------------
# Updated filter: Check if INF property matches the driver file OR the driver name equals the expected model.
$driverInstalled = $false
for ($i = 1; $i -le 3; $i++) {
    try {
        $InstalledDriver = Get-PrinterDriver -ErrorAction Stop | Where-Object { 
            ($_.InfName -like "*$DriverFile*") -or ($_.Name -eq $DriverModel)
        }
        if ($InstalledDriver) {
            $InstalledDriverName = $InstalledDriver.Name
            Write-Log "Printer driver installed successfully. Detected driver name: ${InstalledDriverName}"
            $driverInstalled = $true
            break
        } else {
            Write-Log "Verification attempt ${i}: Printer driver not yet installed. Retrying in 5 seconds..."
            Start-Sleep -Seconds 5
        }
    } catch {
        Write-Log "ERROR during driver verification on attempt ${i}: $_"
        Start-Sleep -Seconds 5
    }
}
if (-not $driverInstalled) {
    Write-Log "ERROR: Printer driver from ${DriverPath} was not installed after multiple attempts."
    Write-Log "DEBUG: Listing all installed printer drivers for troubleshooting:"
    $drivers = Get-PrinterDriver -ErrorAction SilentlyContinue
    foreach ($driver in $drivers) {
        Write-Log "DEBUG: Driver Name: $($driver.Name), INF: $($driver.InfName)"
    }
    exit 1
}

# -------------------------------
# Create Printer Port if it Doesn't Exist (with Retry)
# -------------------------------
$createPortOperation = {
    $existingPort = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
    if (-not $existingPort) {
        Write-Log "Printer port '${PortName}' not found. Creating..."
        Add-PrinterPort -Name $PortName -PrinterHostAddress $PortAddress -ErrorAction Stop
        Write-Log "Created printer port '${PortName}'."
    } else {
        Write-Log "Printer port '${PortName}' already exists."
    }
}
if (-not (Retry-Operation -Operation $createPortOperation -OperationName "Create Printer Port")) {
    Write-Log "ERROR: Failed to create printer port '${PortName}' after multiple attempts. Exiting."
    exit 1
}

# -------------------------------
# Remove Existing Printer Instance (if any) with Retry
# -------------------------------
$removePrinterOperation = {
    $existingPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if ($existingPrinter) {
        Write-Log "Existing printer '${PrinterName}' found. Removing..."
        Remove-Printer -Name $PrinterName -ErrorAction Stop
        Write-Log "Removed existing printer '${PrinterName}'."
    } else {
        Write-Log "No existing printer named '${PrinterName}' found."
    }
}
if (-not (Retry-Operation -Operation $removePrinterOperation -OperationName "Remove Existing Printer")) {
    Write-Log "ERROR: Could not remove existing printer '${PrinterName}' after multiple attempts. Exiting."
    exit 1
}

# -------------------------------
# Create Printer Instance with Retry
# -------------------------------
$createPrinterOperation = {
    Add-Printer -Name $PrinterName -DriverName $InstalledDriverName -PortName $PortName -ErrorAction Stop
}
if (-not (Retry-Operation -Operation $createPrinterOperation -OperationName "Add Printer Instance")) {
    Write-Log "ERROR: Failed to install printer '${PrinterName}' after multiple attempts. Exiting."
    exit 1
}

# -------------------------------
# Final Verification (retry up to 3 times)
# -------------------------------
$printerVerified = $false
for ($i = 1; $i -le 3; $i++) {
    try {
        $finalPrinter = Get-Printer -Name $PrinterName -ErrorAction Stop
        if ($finalPrinter) {
            Write-Log "SUCCESS: Printer '${PrinterName}' is present on ${ComputerName}."
            $printerVerified = $true
            break
        }
    } catch {
        Write-Log "Final verification attempt ${i} failed: $_. Retrying in 5 seconds..."
        Start-Sleep -Seconds 5
    }
}
if (-not $printerVerified) {
    Write-Log "ERROR: Printer '${PrinterName}' not found after installation. Exiting."
    exit 1
}

exit 0
