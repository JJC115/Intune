# *********************************************************************
# Intune Win32 App Script: Install HP Smart Universal Printing Driver V3
#
# This script downloads the repository ZIP from GitHub, extracts the "HP" folder,
# then checks if the expected driver ("HP Smart Universal Printing (V3) (v2.07.1)")
# is installed. If not, it runs the HP installer (install.exe) from the downloaded folder.
# After waiting 30 seconds, if the driver still isn’t found, it falls back to installing
# the driver using Add-PrinterDriver with the INF file.
#
# Finally, it checks if the printer ("Admin Printer") exists; if not, it adds the printer,
# and then cleans up temporary files.
#
# Expected published driver name:
$DriverModel = "HP Smart Universal Printing (V3) (v2.07.1)"

# Printer and port details:
$PrinterName = "Admin Printer"
$PortName    = "IP_10.10.3.210"
$PortAddress = "10.10.3.210"

# ---------------------------------------------------------------------
# Step A: Download the repository ZIP from GitHub.
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
# Step B: Extract the ZIP file.
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
# Step C: Set the source folder to the HP folder from the extracted ZIP.
# The HP folder is expected at: "<ExtractDir>\Intune-main\HP"
# ---------------------------------------------------------------------
$SourceFolder = Join-Path -Path $ExtractDir -ChildPath "Intune-main\HP"
if (-not (Test-Path $SourceFolder)) {
    Write-Error "HP folder not found at '$SourceFolder'. Exiting."
    exit 1
}

# Define paths for the installer and INF file.
$InstallerPath = Join-Path -Path $SourceFolder -ChildPath "install.exe"
$DriverInf = "HPOneDriver.4081_V3_x64.inf"
$PackageDriverInfPath = Join-Path -Path $SourceFolder -ChildPath $DriverInf

if (-not (Test-Path $InstallerPath)) {
    Write-Error "HP installer not found at '$InstallerPath'. Exiting."
    exit 1
}
if (-not (Test-Path $PackageDriverInfPath)) {
    Write-Error "Driver INF file not found at '$PackageDriverInfPath'. Exiting."
    exit 1
}

# ---------------------------------------------------------------------
# Step D: Create the printer port if it doesn't exist.
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
# Step E: Check if the expected driver is installed.
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

# After installer, check again for the driver.
$installedDriver = Get-PrinterDriver -Name $DriverModel -ErrorAction SilentlyContinue
if (-not $installedDriver) {
    Write-Output "Driver '$DriverModel' still not found after installer. Falling back to installing driver via INF."
    try {
        Add-PrinterDriver -Name $DriverModel -InfPath $PackageDriverInfPath -ErrorAction Stop
        Write-Output "Driver installed via Add-PrinterDriver."
    } catch {
        Write-Error "Add-PrinterDriver failed: $_"
        exit 1
    }
} else {
    Write-Output "Driver '$DriverModel' is now installed."
}

# ---------------------------------------------------------------------
# Step F: Check if the printer is installed.
# ---------------------------------------------------------------------
$printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if ($printer) {
    Write-Output "Printer '$PrinterName' is already installed. Exiting script."
    # Clean up temporary files.
    Remove-Item -Path $TempDir -Recurse -Force
    exit 0
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
# Step G: Clean up temporary files.
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
