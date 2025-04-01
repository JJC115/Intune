# *********************************************************************
# Admin Printer Installation Script
# Target Printer: Admin Printer
# IP Address: 10.10.3.210
#
# Expected driver: HP Smart Universal Printing (V3) (v2.07.1)
#
# This script downloads the repository ZIP from GitHub, extracts the "HP" folder,
# then checks if the expected driver is installed. If not, it runs the HP installer
# (install.exe) from the downloaded HP folder and waits 30 seconds.
# Finally, it checks if the printer ("Admin Printer") is installed and adds it if missing,
# then cleans up temporary files.
# *********************************************************************

# Expected published driver name:
$DriverModel = "HP Smart Universal Printing (V3) (v2.07.1)"

# Printer and port details:
$PrinterName = "Admin Printer"
$PortName    = "IP_10.10.3.210"
$PortAddress = "10.10.3.210"

# ---------------------------------------------------------------------
# Step 1: Download repository ZIP from GitHub.
# ---------------------------------------------------------------------
$DownloadUrl = "https://github.com/JJC115/Intune/archive/refs/heads/main.zip"
$TempDir = Join-Path -Path $env:TEMP -ChildPath "IntuneDownload"
if (Test-Path $TempDir) { Remove-Item -Path $TempDir -Recurse -Force }
New-Item -ItemType Directory -Path $TempDir | Out-Null
$ZipFile = Join-Path -Path $TempDir -ChildPath "main.zip"
Write-Output "Downloading repository ZIP from GitHub..."
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFile -UseBasicParsing -ErrorAction Stop
    Write-Output "Download complete."
} catch {
    Write-Error "Download failed: $_"
    exit 1
}

# ---------------------------------------------------------------------
# Step 2: Extract the ZIP file.
# ---------------------------------------------------------------------
$ExtractDir = Join-Path -Path $TempDir -ChildPath "Extracted"
try {
    Expand-Archive -Path $ZipFile -DestinationPath $ExtractDir -Force -ErrorAction Stop
    Write-Output "Extraction complete."
} catch {
    Write-Error "Extraction failed: $_"
    exit 1
}

# ---------------------------------------------------------------------
# Step 3: Set source folder to the HP folder.
# The HP folder is expected at: "<ExtractDir>\Intune-main\HP"
# ---------------------------------------------------------------------
$SourceFolder = Join-Path -Path $ExtractDir -ChildPath "Intune-main\HP"
if (-not (Test-Path $SourceFolder)) {
    Write-Error "HP folder not found at '$SourceFolder'. Exiting."
    exit 1
}

# Define the path to the installer.
$InstallerPath = Join-Path -Path $SourceFolder -ChildPath "install.exe"
if (-not (Test-Path $InstallerPath)) {
    Write-Error "HP installer not found at '$InstallerPath'. Exiting."
    exit 1
}

# ---------------------------------------------------------------------
# Step 4: Create the printer port if it doesn't exist.
# ---------------------------------------------------------------------
$existingPort = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
if (-not $existingPort) {
    Write-Output "Creating printer port '$PortName' with address '$PortAddress'..."
    try {
        Add-PrinterPort -Name $PortName -PrinterHostAddress $PortAddress -ErrorAction Stop
        Write-Output "Printer port created."
    } catch {
        Write-Error "Failed to create printer port. Error: $_"
        exit 1
    }
} else {
    Write-Output "Printer port '$PortName' already exists."
}

# ---------------------------------------------------------------------
# Step 5: Check if the expected driver is installed.
# ---------------------------------------------------------------------
$installedDriver = Get-PrinterDriver -Name $DriverModel -ErrorAction SilentlyContinue
if ($installedDriver) {
    Write-Output "Driver '$DriverModel' is already installed. Skipping installer."
} else {
    Write-Output "Driver '$DriverModel' not found. Running HP installer..."
    try {
        & $InstallerPath /n "$PrinterName" /sm "$PortName" /h /q /nd /u
        Write-Output "HP installer executed. Waiting 30 seconds..."
        Start-Sleep -Seconds 30
    } catch {
        Write-Error "HP installer execution failed: $_"
        exit 1
    }
}

# ---------------------------------------------------------------------
# Step 6: Check if the printer is installed; if not, add it.
# ---------------------------------------------------------------------
$printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if ($printer) {
    Write-Output "Printer '$PrinterName' is already installed."
} else {
    Write-Output "Printer '$PrinterName' not found. Adding printer using the installed driver..."
    try {
        Add-Printer -Name $PrinterName -DriverName $DriverModel -PortName $PortName -ErrorAction Stop
        Write-Output "Printer '$PrinterName' added successfully."
    } catch {
        Write-Error "Failed to add printer '$PrinterName'. Error: $_"
        exit 1
    }
}

# ---------------------------------------------------------------------
# Step 7: Clean up temporary files.
# ---------------------------------------------------------------------
Write-Output "Cleaning up temporary files..."
try {
    Remove-Item -Path $TempDir -Recurse -Force
    Write-Output "Temporary files removed."
} catch {
    Write-Warning "Failed to remove temporary directory '$TempDir'. Please remove it manually."
}

Write-Output "Script completed successfully."
exit 0
