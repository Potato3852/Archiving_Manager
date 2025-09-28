# log_manager.ps1
param(
    [string]$Directory,
    [int]$Limit,
    [int]$N
)

$BACKUP = "backup"

# Check arguments
if ($args.Count -ne 3) {
    Write-Error "Error: give 3 args in format <directory> <limit in MB> <percentage threshold>"
    exit 1
}

# Check directory exists
if (-not (Test-Path $Directory -PathType Container)) {
    Write-Error "Error: Directory '$Directory' does not exist"
    exit 1
}

if ($Limit -eq 0) {
    Write-Error "Error: Limit cannot be zero"
    exit 1
}

# Check write permission
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

# Calculate directory size and percentage
$SizeMB = [math]::Round((Get-ChildItem -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB)
Write-Host "Directory size: ${SizeMB}MB"

$Percentage = [math]::Round(($SizeMB / $Limit) * 100)
Write-Host "CURRENT percentage: ${Percentage} of limit"

# First scenario: Within limits - apply quota
if ($Percentage -le (100 + $N)) {
    Write-Host " Within threshold limits, no archiving needed"
    Write-Host "Applying folder size restriction to prevent exceeding limit..."
    
    # Create VHD with exact size limit
    $VhdPath = "C:\limited_$(Split-Path $Directory -Leaf).vhdx"
    $SizeBytes = $Limit * 1MB
    
    # Create and mount VHD
    New-VHD -Path $VhdPath -SizeBytes $SizeBytes -Dynamic | Mount-VHD -Passthru | 
    Initialize-Disk -Passthru | New-Partition -AssignDriveLetter -UseMaximumSize | 
    Format-Volume -FileSystem NTFS -Confirm:$false | Out-Null
    
    # Get the new drive letter
    $NewDrive = (Get-Partition | Where-Object { $_.Type -eq 'Basic' } | Sort-Object DriveLetter | Select-Object -Last 1).DriveLetter + ":"
    
    # Backup current content
    $TempBackup = Join-Path $env:TEMP "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $TempBackup -Force | Out-Null
    Copy-Item -Path "$Directory\*" -Destination $TempBackup -Recurse -Force
    
    # Move content to new limited drive
    Remove-Item -Path "$Directory\*" -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "$TempBackup\*" -Destination $NewDrive -Recurse -Force
    
    # Create junction point
    cmd.exe /c "rmdir `"$Directory`" 2>nul"
    cmd.exe /c "mklink /J `"$Directory`" `"$NewDrive`""
    
    # Cleanup
    Remove-Item $TempBackup -Recurse -Force
    
    Write-Host "Folder now has hard limit of ${Limit}MB"
    exit 0
}

# Create backup directory if it doesn't exist
if (-not (Test-Path $BACKUP -PathType Container)) {
    New-Item -ItemType Directory -Path $BACKUP -Force | Out-Null
}

# Check backup directory write permission
try {
    $testFile = Join-Path $BACKUP "test_write_access.tmp"
    [IO.File]::WriteAllText($testFile, "test")
    Remove-Item $testFile -Force
}
catch {
    Write-Error "Error: No write permission for backup directory '$BACKUP'"
    exit 1
}

# Second scenario: Exceeds limit - archive files
$ArchivedCount = 0
$FilesToArchive = @()

Write-Host "Starting archiving process to reduce directory size..."

while ($Percentage -gt (100 + $N)) {
    # Find the oldest file (excluding backup directory)
    $OldestFile = Get-ChildItem -File | 
                  Where-Object { $_.FullName -notlike "*\$BACKUP\*" } |
                  Sort-Object LastWriteTime | 
                  Select-Object -First 1
    
    if (-not $OldestFile) {
        Write-Host "No more files found to archive"
        break
    }
    
    $FilesToArchive += $OldestFile
    Write-Host "Adding to archive: $($OldestFile.Name)"
    
    # Recalculate size
    $SizeMB = [math]::Round((Get-ChildItem -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB)
    $Percentage = [math]::Round(($SizeMB / $Limit) * 100)
    
    # Archive in batches of 5 files or when within limit
    if ($FilesToArchive.Count -ge 5 -or $Percentage -le (100 + $N)) {
        if ($FilesToArchive.Count -gt 0) {
            $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $ArchiveName = "$BACKUP\logs_backup_$Timestamp.zip"
            
            Write-Host "Creating archive with $($FilesToArchive.Count) files..."
            Compress-Archive -Path $FilesToArchive.FullName -DestinationPath $ArchiveName -Force
            
            Write-Host "Removing archived files..."
            $FilesToArchive | Remove-Item -Force
            
            $ArchivedCount += $FilesToArchive.Count
            $FilesToArchive = @()
        }
    }
}

# Archive any remaining files
if ($FilesToArchive.Count -gt 0) {
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $ArchiveName = "$BACKUP\logs_backup_$Timestamp.zip"
    
    Write-Host "Creating final archive with $($FilesToArchive.Count) files..."
    Compress-Archive -Path $FilesToArchive.FullName -DestinationPath $ArchiveName -Force
    Write-Host "Removing archived files..."
    $FilesToArchive | Remove-Item -Force
    $ArchivedCount += $FilesToArchive.Count
}

# Apply HARD folder size restriction using VHD
Write-Host "Applying HARD folder size restriction..."
$SizeMB = [math]::Round((Get-ChildItem -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB)

Write-Host "Creating VHD with hard limit of ${Limit}MB..."
$VhdPath = "C:\limited_$(Split-Path $Directory -Leaf).vhdx"
$SizeBytes = $Limit * 1MB

# Create and mount VHD
New-VHD -Path $VhdPath -SizeBytes $SizeBytes -Dynamic | Mount-VHD -Passthru | 
Initialize-Disk -Passthru | New-Partition -AssignDriveLetter -UseMaximumSize | 
Format-Volume -FileSystem NTFS -Confirm:$false | Out-Null

# Get the new drive letter
$NewDrive = (Get-Partition | Where-Object { $_.Type -eq 'Basic' } | Sort-Object DriveLetter | Select-Object -Last 1).DriveLetter + ":"

# Backup current content
$TempBackup = Join-Path $env:TEMP "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $TempBackup -Force | Out-Null
Copy-Item -Path "$Directory\*" -Destination $TempBackup -Recurse -Force

# Move content to new limited drive and create junction
Remove-Item -Path "$Directory\*" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path "$TempBackup\*" -Destination $NewDrive -Recurse -Force

# Remove old directory and create junction point
cmd.exe /c "rmdir `"$Directory`" 2>nul"
cmd.exe /c "mklink /J `"$Directory`" `"$NewDrive`""

# Cleanup
Remove-Item $TempBackup -Recurse -Force

$NewSizeMB = [math]::Round((Get-ChildItem -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB)
$NewPercentage = [math]::Round(($NewSizeMB / $Limit) * 100)
$FreedSpace = $SizeMB - $NewSizeMB

Write-Host "=== Results ==="
Write-Host "Files archived: $ArchivedCount"
Write-Host "New size: ${NewSizeMB}MB"
Write-Host "New percentage: ${NewPercentage}%"
Write-Host "Freed space: ${FreedSpace}MB"
Write-Host "Folder now has HARD limit of ${Limit}MB - impossible to exceed!"
