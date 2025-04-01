# *********************************************************************
# Install Script: HRT Printer #2
# Target Printer: HRT Printer #2
# IP Address: 10.10.3.205
#
# Expected driver: HP Smart Universal Printing (V3) (v2.07.1)
# *********************************************************************

$DriverModel = "HP Smart Universal Printing (V3) (v2.07.1)"
$PrinterName = "HRT Printer #2"
$PortName    = "IP_10.10.3.205"
$PortAddress = "10.10.3.205"

$DownloadUrl = "https://github.com/JJC115/Intune/archive/refs/heads/main.zip"
$TempDir = Join-Path -Path $env:TEMP -ChildPath "IntuneDownload"
if (Test-Path $TempDir) { Remove-Item -Path $TempDir -Recurse -Force }
New-Item -ItemType Directory -Path $TempDir | Out-Null
$ZipFile = Join-Path -Path $TempDir -ChildPath "main.zip"
Write-Output "Downloading repository ZIP from GitHub..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFile -UseBasicParsing -ErrorAction Stop
Write-Output "Download complete."
$ExtractDir = Join-Path -Path $TempDir -ChildPath "Extracted"
Expand-Archive -Path $ZipFile -DestinationPath $ExtractDir -Force -ErrorAction Stop
Write-Output "Extraction complete."
$SourceFolder = Join-Path -Path $ExtractDir -ChildPath "Intune-main\HP"
if (-not (Test-Path $SourceFolder)) {
    Write-Error "HP folder not found at '$SourceFolder'. Exiting."
    exit 1
}
$InstallerPath = Join-Path -Path $SourceFolder -ChildPath "install.exe"
if (-not (Test-Path $InstallerPath)) {
    Write-Error "HP installer not found at '$InstallerPath'. Exiting."
    exit 1
}

$existingPort = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
if (-not $existingPort) {
    Write-Output "Creating printer port '$PortName' with address '$PortAddress'..."
    Add-PrinterPort -Name $PortName -PrinterHostAddress $PortAddress -ErrorAction Stop
    Write-Output "Printer port created."
} else {
    Write-Output "Printer port '$PortName' already exists."
}

$installedDriver = Get-PrinterDriver -Name $DriverModel -ErrorAction SilentlyContinue
if ($installedDriver) {
    Write-Output "Driver '$DriverModel' is already installed. Skipping installer."
} else {
    Write-Output "Driver '$DriverModel' not found. Running HP installer..."
    & $InstallerPath /n "$PrinterName" /sm "$PortName" /h /q /nd /u
    Write-Output "HP installer executed. Waiting 30 seconds..."
    Start-Sleep -Seconds 30
}

$printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if ($printer) {
    Write-Output "Printer '$PrinterName' is already installed."
} else {
    Write-Output "Printer '$PrinterName' not found. Adding printer..."
    Add-Printer -Name $PrinterName -DriverName $DriverModel -PortName $PortName -ErrorAction Stop
    Write-Output "Printer '$PrinterName' added successfully."
}

Write-Output "Cleaning up temporary files..."
Remove-Item -Path $TempDir -Recurse -Force
Write-Output "Script completed successfully."
exit 0