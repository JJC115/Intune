# ================================
# Fresh Intune Printer Installer
# ================================

# --- Key Variables (adjust as needed) ---
$ScriptRoot    = if ($PSScriptRoot -and $PSScriptRoot -ne "") { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$DriverFile    = "HPOneDriver.4081_V3_x64.inf"               # INF file name
$DriverPath    = Join-Path $ScriptRoot $DriverFile            # Full path to INF file
$DriverModel   = "HP Smart Universal Printing (V3) (v2.07.1)" # Driver model name as defined in the INF
$PrinterName   = "Admin Printer"                              # Desired printer display name
$PortName      = "IP_10.10.3.210"                             # Printer port name (using the IP)
$PortAddress   = "10.10.3.210"                                # Port address
$LogFile       = "C:\ProgramData\PrinterInstall.log"          # Log file location

# -------------------------------
# Initialize Logging
# -------------------------------
if (Test-Path $LogFile) { Remove-Item $LogFile -Force }
New-Item -Path $LogFile -ItemType File -Force | Out-Null
function Write-Log($message) {
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timeStamp - $message"
    Add-Content -Path $LogFile -Value $entry
    Write-Output $entry
}

Write-Log "=== Starting Printer Installation ==="
Write-Log "Script folder: $ScriptRoot"
Write-Log "Driver file path: $DriverPath"

# -------------------------------
# Verify the Driver File Exists
# -------------------------------
if (!(Test-Path $DriverPath)) {
    Write-Log "ERROR: Driver file not found at $DriverPath. Exiting."
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
    Write-Log "ERROR: Could not remove printer '$PrinterName': $_"
    exit 1
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
# Install Printer using PrintUIEntry
# -------------------------------
# Build PrintUIEntry arguments:
#   /if : Install printer using the INF file
#   /b  : Printer display name
#   /f  : Full path to the INF file
#   /r  : Printer port name
#   /m  : Printer driver model name
#   /q  : Quiet mode
$arguments = "/if /b `"$PrinterName`" /f `"$DriverPath`" /r `"$PortName`" /m `"$DriverModel`" /q"
Write-Log "Executing: rundll32.exe printui.dll,PrintUIEntry $arguments"
try {
    $proc = Start-Process -FilePath "rundll32.exe" -ArgumentList "printui.dll,PrintUIEntry $arguments" -NoNewWindow -Wait -PassThru
    Write-Log "PrintUIEntry exited with code: $($proc.ExitCode)"
} catch {
    Write-Log "ERROR: PrintUIEntry execution failed: $_"
    exit 1
}

Start-Sleep -Seconds 5

# -------------------------------
# Verify Printer Installation
# -------------------------------
$installedPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if (-not $installedPrinter) {
    Write-Log "Printer '$PrinterName' not found after PrintUIEntry. Attempting fallback with Add-Printer..."
    try {
        Add-Printer -Name $PrinterName -PortName $PortName -DriverName $DriverModel -ErrorAction Stop
        Write-Log "Printer instance created using Add-Printer."
    } catch {
        Write-Log "ERROR: Add-Printer failed: $_"
        exit 1
    }
    Start-Sleep -Seconds 5
    $installedPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if ($installedPrinter) {
        Write-Log "SUCCESS: Printer '$PrinterName' installed successfully via fallback."
        exit 0
    } else {
        Write-Log "ERROR: Printer '$PrinterName' still not found after fallback."
        exit 1
    }
} else {
    Write-Log "SUCCESS: Printer '$PrinterName' installed successfully via PrintUIEntry."
    exit 0
}
