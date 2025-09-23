# log_manager.ps1
param(
    [string]$Directory,
    [int]$Limit,
    [int]$M
)

$BACKUP = "backup"

# Checking numbers of arguments 
if ($args.Count -ne 3) {
    Write-Error "Error: give 3 args in format <directory> <limit in MB> <numbers of zip files>"
    exit 1
}

# Cheking directory existance
if (-not (Test-Path $Directory -PathType Container)) {
    Write-Error "Error: Directory '$Directory' does not exist"
    exit 1
}

if ($M -le 0) {
    Write-Error "Error: Number of files to archive must be a positive integer"
    exit 1
}

if ($Limit -eq 0) {
    Write-Error "Error: Limit cannot be zero"
    exit 1
}

# cheking rules of status
try {
    $testFile = Join-Path $Directory "test_write_access.tmp"
    [IO.File]::WriteAllText($testFile, "test")
    Remove-Item $testFile -Force
}
catch {
    Write-Error "Error: No write permission for directory '$Directory'"
    exit 1
}

Set-Location $Directory

# SIZE of dir and percentage
$SizeMB = [math]::Round((Get-ChildItem -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB)
Write-Host "Directory size: ${SizeMB}MB"

$Percentage = [math]::Round(($SizeMB / $Limit) * 100)
Write-Host "CURRENT percentage: ${Percentage} of limit"

if ($Percentage -le 100) {
    Write-Host " Within threshold limits, no archiving needed"
    exit 0
}

# Find the M oldest files
$OldestFiles = Get-ChildItem -File | Sort-Object LastWriteTime | Select-Object -First $M

if ($OldestFiles.Count -eq 0) {
    Write-Host "No files found to archive"
    exit 0
}

Write-Host "Files to archive:"
$OldestFiles | ForEach-Object { Write-Host $_.Name }

# Создаем папку backup если не существует
if (-not (Test-Path $BACKUP -PathType Container)) {
    New-Item -ItemType Directory -Path $BACKUP -Force | Out-Null
}

try {
    $testFile = Join-Path $BACKUP "test_write_access.tmp"
    [IO.File]::WriteAllText($testFile, "test")
    Remove-Item $testFile -Force
}
catch {
    Write-Error "Error: No write permission for backup directory '$BACKUP'"
    exit 1
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ArchiveName = "$BACKUP\logs_backup_$Timestamp.zip"

Write-Host "Creating archive $ArchiveName"
Compress-Archive -Path $OldestFiles.FullName -DestinationPath $ArchiveName -Force

Write-Host "Removing old files..."
$OldestFiles | Remove-Item -Force

$NewSizeMB = [math]::Round((Get-ChildItem -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB)
$NewPercentage = [math]::Round(($NewSizeMB / $Limit) * 100)
$FreedSpace = $SizeMB - $NewSizeMB

Write-Host "=== Results ==="
Write-Host "New size: ${NewSizeMB}MB"
Write-Host "New percentage: ${NewPercentage}%"
Write-Host "Freed space: ${FreedSpace}MB"
Write-Host "Archive created: $ArchiveName"
