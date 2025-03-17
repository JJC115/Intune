# ==========================================
# Intune Printer Installer Script with Download from GitHub, Failovers, and Cleanup
# ==========================================
# This script:
#   • Creates a temporary directory and downloads the printer driver file from GitHub
#   • Unblocks and installs the driver via pnputil.exe with retry logic and output capture
#   • Verifies the driver installation (by checking both INF and Driver Name)
#   • Creates the printer port if it doesn’t exist (with retries)
#   • Removes any existing instance of the printer (with retries)
#   • Creates the printer instance using Add-Printer (with retries)
#   • Logs every step to a network share log file
#   • Deletes the temporary directory after completion
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

# --- GitHub URL for the driver file (raw link) ---
$DriverDownloadURL = "https://raw.githubusercontent.com/JJC115/Intune/main/HP-Drivers/HPOneDriver.4081_V3_x64.inf"

# --- Determine Computer Name and log file path on network share ---
$ComputerName = $env:COMPUTERNAME
$LogFile = "C:\logs\printer-logs\PrinterInstall_${ComputerName}.log"

# --- Determine Script Root (for logging only) ---
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $ScriptRoot = $PSScriptRoot
} else {
    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

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
Write-Log "Using driver download URL: ${DriverDownloadURL}"

# -------------------------------
# Create Temporary Directory and Download Driver
# -------------------------------
# Create a temp directory
$tempDirPath = Join-Path -Path $env:TEMP -ChildPath ([System.IO.Path]::GetRandomFileName())
$tempDir = New-Item -ItemType Directory -Path $tempDirPath -Force
Write-Log "Created temporary directory: ${tempDir.FullName}"

try {
    # Download the driver file from GitHub to the temp directory
    $DownloadedDriverPath = Join-Path -Path $tempDir.FullName -ChildPath $DriverFile
    Write-Log "Downloading driver file from ${DriverDownloadURL} to ${DownloadedDriverPath}..."
    Invoke-WebRequest -Uri $DriverDownloadURL -OutFile $DownloadedDriverPath -UseBasicParsing
    Write-Log "Download complete."
    
    # Set the driver path to the downloaded file
    $DriverPath = $DownloadedDriverPath

    # -------------------------------
    # Verify Driver File Exists and Unblock It
    # -------------------------------
    if (-not (Test-Path $DriverPath)) {
        Write-Log "ERROR: Driver file not found at ${DriverPath}. Exiting."
        exit 1
    }
    
    try {
        Unblock-File -Path $DriverPath -ErrorAction Stop
        Write-Log "Unblocked driver file at ${DriverPath}."
    } catch {
        Write-Log "WARNING: Failed to unblock driver file at ${DriverPath}: $_"
    }
    
    # -------------------------------
    # Determine Correct pnputil.exe Path
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
    # Install Printer Driver using pnputil.exe with Retry and Output Capture
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
        Write-Log "pnputil returned exit code –536870353 (0xE000022F). This error often indicates a problem with driver package acceptance (e.g. blocked file, signature or architecture mismatch)."
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

} finally {
    # Clean up: delete the temporary directory
    if (Test-Path $tempDir.FullName) {
        Remove-Item -Path $tempDir.FullName -Recurse -Force
        Write-Log "Temporary directory ${tempDir.FullName} removed."
    }
}
