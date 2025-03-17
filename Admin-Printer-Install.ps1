#########################################
# Final Intune Printer Installer Script (with network logging)
#########################################
# This script:
#   • Installs the printer driver using pnputil.exe
#   • Verifies the driver installation
#   • Creates the printer port if it doesn’t exist
#   • Creates the printer instance using Add-Printer
#   • Logs every step to a log file on the network share, including the computer name
#########################################

# --- Key Variables (customize as needed) ---
$DriverFile    = "HPOneDriver.4081_V3_x64.inf"                # INF file name
$DriverModel   = "HP Smart Universal Printing (V3) (v2.07.1)"  # Expected driver model name (from INF)
$PrinterName   = "Admin Printer"                               # Desired printer display name
$PortName      = "IP_10.10.3.210"                              # Printer port name (using the IP)
$PortAddress   = "10.10.3.210"                                 # Port address

# --- Determine the Computer Name and log file path on the network share ---
$ComputerName = $env:COMPUTERNAME
$LogFile = "\\help-fs\share\temp\printer-logs\PrinterInstall_$ComputerName.log"

# --- Determine the script folder (fallback if $PSScriptRoot is empty) ---
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
    param ([string]$message)
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timeStamp - $message"
    Add-Content -Path $LogFile -Value $entry
    Write-Output $entry
}

Write-Log "=== Starting Printer Installation on $ComputerName ==="
Write-Log "Script folder: $ScriptRoot"
Write-Log "Driver file path: $DriverPath"

# -------------------------------
# Verify Driver File Exists
# -------------------------------
if (!(Test-Path $DriverPath)) {
    Write-Log "ERROR: Driver file not found at $DriverPath. Exiting."
    exit 1
}

# -------------------------------
# Install Printer Driver using pnputil.exe
# -------------------------------
$PnPUtilPath = "C:\Windows\System32\pnputil.exe"
if (!(Test-Path $PnPUtilPath)) {
    Write-Log "ERROR: pnputil.exe not found at $PnPUtilPath. Exiting."
    exit 1
}

Write-Log "Installing printer driver via pnputil..."
$pnputilArgs = "/add-driver `"$DriverPath`" /install"
try {
    $p = Start-Process -FilePath $PnPUtilPath -ArgumentList $pnputilArgs -NoNewWindow -Wait -PassThru
    Write-Log "pnputil.exe exit code: $($p.ExitCode)"
} catch {
    Write-Log "ERROR: pnputil.exe failed: $_"
    exit 1
}
Start-Sleep -Seconds 5  # Wait for driver registration

# -------------------------------
# Verify Driver Installation
# -------------------------------
$InstalledDriver = Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.InfName -like "*$DriverFile*" }
if (-not $InstalledDriver) {
    Write-Log "ERROR: Printer driver from $DriverPath was not installed. Exiting."
    exit 1
} else {
    $InstalledDriverName = $InstalledDriver.Name
    Write-Log "Printer driver installed successfully. Detected driver name: $InstalledDriverName"
}

# -------------------------------
# Create Printer Port (if not exists)
# -------------------------------
try {
    $existingPort = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
    if (-not $existingPort) {
        Write-Log "Printer port '$PortName' not found. Creating..."
        Add-PrinterPort -Name $PortName -PrinterHostAddress $PortAddress -ErrorAction Stop
        Write-Log "Created printer port '$PortName'."
    } else {
        Write-Log "Printer port '$PortName' already exists."
    }
} catch {
    Write-Log "ERROR: Failed to create printer port '$PortName': $_"
    exit 1
}

# -------------------------------
# Remove Existing Printer Instance (if any)
# -------------------------------
try {
    $existingPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if ($existingPrinter) {
        Write-Log "Existing printer '$PrinterName' found. Removing..."
        Remove-Printer -Name $PrinterName -ErrorAction Stop
        Write-Log "Removed printer '$PrinterName'."
    } else {
        Write-Log "No existing printer named '$PrinterName' found."
    }
} catch {
    Write-Log "ERROR: Could not remove existing printer '$PrinterName': $_"
    exit 1
}

# -------------------------------
# Create Printer Instance using Add-Printer
# -------------------------------
Write-Log "Creating printer '$PrinterName' using driver '$InstalledDriverName' on port '$PortName'..."
try {
    Add-Printer -Name $PrinterName -DriverName $InstalledDriverName -PortName $PortName -ErrorAction Stop
    Write-Log "Printer '$PrinterName' installed successfully."
} catch {
    Write-Log "ERROR: Failed to install printer '$PrinterName': $_"
    exit 1
}

# -------------------------------
# Final Verification
# -------------------------------
$finalPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if ($finalPrinter) {
    Write-Log "SUCCESS: Printer '$PrinterName' is present on $ComputerName."
    exit 0
} else {
    Write-Log "ERROR: Printer '$PrinterName' not found after installation."
    exit 1
}
