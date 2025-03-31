# ==========================================
# Revised Intune Printer Installer Script
# ==========================================
# This script:
#   - Creates a temporary directory, downloads the printer driver file from GitHub, and unblocks it.
#   - Installs the driver using pnputil.exe with retry logic and output capture.
#   - Verifies the driver installation (by checking both INF and Driver Name).
#   - Creates the printer port if it doesn’t exist (with retries).
#   - Removes any existing instance of the printer (with retries).
#   - Creates the printer instance using Add-Printer (with retries).
#   - Logs every step to a log file.
#   - Deletes the temporary directory after completion.
#
# Note: This script uses Sysnative if running as a 32-bit process on a 64-bit OS.
# ==========================================

# Set strict error handling
$ErrorActionPreference = "Stop"

# --- Configuration Variables (customize as needed) ---
$DriverFile         = "HPOneDriver.4081_V3_x64.inf"                # INF file name
$DriverModel        = "HP Smart Universal Printing (V3) (v2.07.1)"  # Expected driver model name (from INF)
$PrinterName        = "Admin Printer"                               # Desired printer display name
$PortName           = "IP_10.10.3.210"                              # Printer port name (using the IP)
$PortAddress        = "10.10.3.210"                                 # Printer port address
$DriverDownloadURL  = "https://raw.githubusercontent.com/JJC115/Intune/main/HP-Drivers/HPOneDriver.4081_V3_x64.inf"

# --- Log file configuration ---
$ComputerName = $env:COMPUTERNAME
$LogDir       = "C:\logs\printer-logs"
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}
$LogFile = Join-Path -Path $LogDir -ChildPath "PrinterInstall_${ComputerName}.log"

# --- Determine Script Root ---
if ($PSScriptRoot) {
    $ScriptRoot = $PSScriptRoot
} else {
    $ScriptRoot = (Get-Location).Path
}

# -------------------------------
# Logging Function
# -------------------------------
function Write-Log {
    param (
        [string]$Message
    )
    $timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry     = "$timeStamp - $Message"
    Add-Content -Path $LogFile -Value $entry
    Write-Output $entry
}

# Initialize Log File
if (Test-Path $LogFile) { Remove-Item $LogFile -Force }
New-Item -Path $LogFile -ItemType File -Force | Out-Null
Write-Log "=== Starting Printer Installation on ${ComputerName} ==="
Write-Log "Script folder: ${ScriptRoot}"
Write-Log "Using driver download URL: ${DriverDownloadURL}"

try {
    # -------------------------------
    # Create Temporary Directory and Download Driver
    # -------------------------------
    $tempDirPath = Join-Path -Path $env:TEMP -ChildPath ([System.IO.Path]::GetRandomFileName())
    $tempDir     = New-Item -ItemType Directory -Path $tempDirPath -Force
    Write-Log "Created temporary directory: $($tempDir.FullName)"
    
    $DownloadedDriverPath = Join-Path -Path $tempDir.FullName -ChildPath $DriverFile
    Write-Log "Downloading driver file from ${DriverDownloadURL} to ${DownloadedDriverPath}..."
    Invoke-WebRequest -Uri $DriverDownloadURL -OutFile $DownloadedDriverPath -UseBasicParsing
    Write-Log "Download complete."
    
    $DriverPath = $DownloadedDriverPath
    
    if (-not (Test-Path $DriverPath)) {
        Write-Log "ERROR: Driver file not found at ${DriverPath}. Exiting."
        exit 1
    }
    
    try {
        Unblock-File -Path $DriverPath -ErrorAction Stop
        Write-Log "Unblocked driver file at ${DriverPath}."
    } catch {
        Write-Log "WARNING: Failed to unblock driver file at ${DriverPath}: $($_.Exception.Message)"
    }
    
    # -------------------------------
    # Determine pnputil.exe Path
    # -------------------------------
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
    # Retry Function Definition
    # -------------------------------
    function Retry-Operation {
        param(
            [ScriptBlock]$Operation,
            [int]$MaxAttempts = 3,
            [int]$DelaySeconds = 5,
            [string]$OperationName = "Operation"
        )
    
        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            try {
                Write-Log "${OperationName}: Attempt ${attempt}..."
                & $Operation
                return $true
            } catch {
                Write-Log "ERROR: ${OperationName} failed on attempt ${attempt}: $($_.Exception.Message)"
                if ($attempt -lt $MaxAttempts) {
                    Write-Log "${OperationName}: Retrying in ${DelaySeconds} seconds..."
                    Start-Sleep -Seconds $DelaySeconds
                }
            }
        }
        return $false
    }
    
    # -------------------------------
    # Install Printer Driver using pnputil.exe with Retry
    # -------------------------------
    $stdOutFile = Join-Path -Path $tempDir.FullName -ChildPath "pnputil_output.txt"
    $stdErrFile = Join-Path -Path $tempDir.FullName -ChildPath "pnputil_error.txt"
    
    $pnputilArgs = "/add-driver `"$DriverPath`" /install"
    $installDriverOperation = {
        if (Test-Path $stdOutFile) { Remove-Item $stdOutFile -Force }
        if (Test-Path $stdErrFile) { Remove-Item $stdErrFile -Force }
    
        $process = Start-Process -FilePath $PnPUtilPath -ArgumentList $pnputilArgs -NoNewWindow -Wait -PassThru `
                    -RedirectStandardOutput $stdOutFile -RedirectStandardError $stdErrFile
        if ($process.ExitCode -ne 0) {
            throw "pnputil.exe returned exit code $($process.ExitCode)"
        }
    }
    
    if (-not (Retry-Operation -Operation $installDriverOperation -OperationName "Printer driver installation")) {
        Write-Log "ERROR: Printer driver installation failed after multiple attempts."
        Write-Log "pnputil returned an error. Check the output files for details."
        if (Test-Path $stdOutFile) { 
            Write-Log "pnputil standard output:"
            Get-Content $stdOutFile | ForEach-Object { Write-Log "$_" }
        }
        if (Test-Path $stdErrFile) { 
            Write-Log "pnputil standard error:"
            Get-Content $stdErrFile | ForEach-Object { Write-Log "$_" }
        }
        exit 1
    }
    
    Start-Sleep -Seconds 5  # Allow time for driver registration
    
    # -------------------------------
    # Verify Driver Installation
    # -------------------------------
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
            Write-Log "ERROR during driver verification on attempt ${i}: $($_.Exception.Message)"
            Start-Sleep -Seconds 5
        }
    }
    
    if (-not $driverInstalled) {
        Write-Log "ERROR: Printer driver from ${DriverPath} was not installed after multiple attempts."
        Write-Log "DEBUG: Listing all installed printer drivers:"
        Get-PrinterDriver -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log "DEBUG: Driver Name: $($_.Name), INF: $($_.InfName)"
        }
        exit 1
    }
    
    # -------------------------------
    # Create Printer Port if it Doesn't Exist
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
    # Remove Existing Printer Instance (if any)
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
    # Create Printer Instance
    # -------------------------------
    $createPrinterOperation = {
        Add-Printer -Name $PrinterName -DriverName $InstalledDriverName -PortName $PortName -ErrorAction Stop
    }
    
    if (-not (Retry-Operation -Operation $createPrinterOperation -OperationName "Add Printer Instance")) {
        Write-Log "ERROR: Failed to install printer '${PrinterName}' after multiple attempts. Exiting."
        exit 1
    }
    
    # -------------------------------
    # Final Verification of Printer Creation
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
            Write-Log "Final verification attempt ${i} failed: $($_.Exception.Message). Retrying in 5 seconds..."
            Start-Sleep -Seconds 5
        }
    }
    
    if (-not $printerVerified) {
        Write-Log "ERROR: Printer '${PrinterName}' not found after installation. Exiting."
        exit 1
    }
    
    exit 0

} finally {
    # -------------------------------
    # Cleanup: Remove Temporary Directory
    # -------------------------------
    if ($tempDir -and (Test-Path $tempDir.FullName)) {
        Remove-Item -Path $tempDir.FullName -Recurse -Force
        Write-Log "Temporary directory $($tempDir.FullName) removed."
    }
}