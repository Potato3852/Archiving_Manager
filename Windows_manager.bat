# log_manager.ps1
param(
    [string]$Directory,
    [string]$LimitInput,
    [int]$N
)

# Check arguments
if ($args.Count -ne 3) {
    Write-Error "Error: give 3 args in format <directory> <limit> <percentage threshold>"
    Write-Host "Limit can be in KB, MB, GB, TB (e.g., 1G, 500M, 2.5GB)"
    Write-Host "Example: .\log_manager.ps1 C:\Logs 1G 20"
    exit 1
}

# Function to convert to megabytes
function To-Megabytes {
    param([string]$Value)
    
    $Value = $Value -replace '\s', ''  # Remove spaces
    $Value = $Value.ToLower()
    
    # Extract number and unit
    if ($Value -match '^(\d+(\.\d+)?)([kmgt]b?)?$') {
        $Num = [double]$Matches[1]
        $Unit = $Matches[3]
        
        switch ($Unit) {
            "k" { "kb" } { return $Num / 1024 }
            "m" { "mb" } { return $Num }
            "g" { "gb" } { return $Num * 1024 }
            "t" { "tb" } { return $Num * 1024 * 1024 }
            default { return $Num }
        }
    } else {
        Write-Error "Invalid size format: $Value"
        exit 1
    }
}

# Check directory exists
if (-not (Test-Path $Directory -PathType Container)) {
    Write-Error "Error: Directory '$Directory' does not exist"
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

# Convert limit to MB
$LimitMB = [math]::Round((To-Megabytes $LimitInput))
if ($LimitMB -eq 0) {
    Write-Error "Error: Limit cannot be zero"
    exit 1
}

$BACKUP = "backup"
$FullDirectory = (Resolve-Path $Directory).Path
Set-Location $FullDirectory

# Calculate directory size
$SizeMB = [math]::Round((Get-ChildItem -Recurse -Force | Measure-Object -Property Length -Sum).Sum / 1MB)
$ArchiveTrigger = [math]::Round($LimitMB * $N / 100)

Write-Host "Directory size: ${SizeMB}MB"
Write-Host "Limit: ${LimitMB}MB"
Write-Host "Archive trigger: ${ArchiveTrigger}MB"

$Percentage = [math]::Round(($SizeMB / $LimitMB) * 100)
Write-Host "CURRENT percentage: ${Percentage}% of limit"

# First scenario
#----------------------------------------------------------------------
if ($SizeMB -le $ArchiveTrigger) {
    Write-Host "Within threshold limits, no archiving needed"
    Write-Host "Applying folder size restriction to prevent exceeding limit..."
    
    # Create VHD with exact size limit
    $VhdPath = "C:\limited_$(Split-Path $Directory -Leaf).vhdx"
    $SizeBytes = $LimitMB * 1MB
    
    # Check if VHD already exists
    if (Test-Path $VhdPath) {
        Write-Host "VHD file $VhdPath already exists. Overwriting..."
        Remove-Item $VhdPath -Force -ErrorAction SilentlyContinue
    }
    
    # Create and mount VHD
    try {
        $disk = New-VHD -Path $VhdPath -SizeBytes $SizeBytes -Dynamic | Mount-VHD -Passthru
        $disk | Initialize-Disk -Passthru | New-Partition -AssignDriveLetter -UseMaximumSize | 
        Format-Volume -FileSystem NTFS -Confirm:$false | Out-Null
        
        # Get the new drive letter
        $NewDrive = (Get-Partition -DiskNumber $disk.DiskNumber | Where-Object { $_.DriveLetter } | Select-Object -Last 1).DriveLetter + ":\"
        
        # Backup current content
        $TempBackup = Join-Path $env:TEMP "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $TempBackup -Force | Out-Null
        Copy-Item -Path "$FullDirectory\*" -Destination $TempBackup -Recurse -Force
        
        # Move content to new limited drive
        Remove-Item -Path "$FullDirectory\*" -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -Path "$TempBackup\*" -Destination $NewDrive -Recurse -Force
        
        # Create junction point
        cmd.exe /c "rmdir `"$FullDirectory`" 2>nul"
        cmd.exe /c "mklink /J `"$FullDirectory`" `"$NewDrive`""
        
        # Cleanup
        Remove-Item $TempBackup -Recurse -Force
        
        Write-Host "Folder now has hard limit of ${LimitInput}"
    }
    catch {
        Write-Error "Error creating VHD: $($_.Exception.Message)"
        exit 1
    }
    exit 0
}

# Second scenario
#---------------------------------------------------------
Write-Host "Size exceeds threshold, archiving required"
Write-Host "Starting archiving process..."

# Create backup directory if it doesn't exist
$BackupDir = Join-Path $FullDirectory $BACKUP
if (-not (Test-Path $BackupDir -PathType Container)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

# Check backup directory write permission
try {
    $testFile = Join-Path $BackupDir "test_write_access.tmp"
    [IO.File]::WriteAllText($testFile, "test")
    Remove-Item $testFile -Force
}
catch {
    Write-Error "Error: No write permission for backup directory '$BackupDir'"
    exit 1
}

Write-Host "WARNING: Usage exceeds $N% limit! Calculating files to archive..."
    
$SpaceToFree = $SizeMB - $ArchiveTrigger
Write-Host "Need to free approximately $SpaceToFree MB"

# Find all files (excluding backup directory), sort by last write time (oldest first)
$AllFiles = Get-ChildItem -Path $FullDirectory -File -Recurse -Force | 
            Where-Object { $_.FullName -notlike "*\$BACKUP\*" } |
            Sort-Object LastWriteTime

if ($AllFiles.Count -eq 0) {
    Write-Host "No files found to archive."
    exit 0
}

# Select files to archive until we free enough space
$FilesToArchive = @()
$CurrentFreed = 0
$FileCount = 0

foreach ($File in $AllFiles) {
    $FileSizeMB = [math]::Round($File.Length / 1MB)
    
    if ($CurrentFreed -lt $SpaceToFree -or $FileCount -eq 0) {
        $FilesToArchive += $File
        $CurrentFreed += $FileSizeMB
        $FileCount++
    } else {
        break
    }
}

if ($FileCount -eq 0) {
    Write-Host "No files selected for archiving."
    exit 0
}

Write-Host "Selected $FileCount files to archive (~$CurrentFreed MB)"

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ArchiveName = "$BackupDir\backup_$Timestamp.zip"

Write-Host "Creating archive: $ArchiveName"

try {
    # Create archive
    Compress-Archive -Path $FilesToArchive.FullName -DestinationPath $ArchiveName -Force
    $ArchiveSize = [math]::Round((Get-Item $ArchiveName).Length / 1MB)
    
    Write-Host "Archive created successfully: $ArchiveName"
    Write-Host "Archive size: ${ArchiveSize}MB"
    
    # Remove original files
    Write-Host "Removing original files..."
    $RemovedCount = 0
    foreach ($File in $FilesToArchive) {
        try {
            Remove-Item $File.FullName -Force
            $RemovedCount++
        }
        catch {
            Write-Warning "Could not remove $($File.FullName)"
        }
    }
    
    Write-Host "Original files removed: $RemovedCount files"
    
    # Calculate new size
    $NewSize = [math]::Round((Get-ChildItem -Path $FullDirectory -Recurse -Force | Measure-Object -Property Length -Sum).Sum / 1MB)
    $NewRatio = [math]::Round(($NewSize / $LimitMB) * 100)
    
    Write-Host "Archiving completed:"
    Write-Host "- Original size: $SizeMB MB"
    Write-Host "- New size: $NewSize MB" 
    Write-Host "- New fill ratio: $NewRatio%"
    Write-Host "- Files archived: $FileCount"
    Write-Host "- Approximate space freed: $CurrentFreed MB"
    
    if ($NewSize -le $ArchiveTrigger) {
        Write-Host "SUCCESS: Directory size is now below archive threshold!"
    } else {
        Write-Host "WARNING: Directory size still exceeds threshold. Consider running script again."
    }
}
catch {
    Write-Error "Error creating archive: $($_.Exception.Message)"
    exit 1
}

# Apply hard limit after archiving
Write-Host "Applying HARD folder size restriction..."
Write-Host "Creating VHD with hard limit of ${LimitInput}..."

$VhdPath = "C:\limited_$(Split-Path $Directory -Leaf).vhdx"
$SizeBytes = $LimitMB * 1MB

# Check if VHD already exists
if (Test-Path $VhdPath) {
    Write-Host "VHD file $VhdPath already exists. Overwriting..."
    Remove-Item $VhdPath -Force -ErrorAction SilentlyContinue
}

try {
    # Create and mount VHD
    $disk = New-VHD -Path $VhdPath -SizeBytes $SizeBytes -Dynamic | Mount-VHD -Passthru
    $disk | Initialize-Disk -Passthru | New-Partition -AssignDriveLetter -UseMaximumSize | 
    Format-Volume -FileSystem NTFS -Confirm:$false | Out-Null
    
    # Get the new drive letter
    $NewDrive = (Get-Partition -DiskNumber $disk.DiskNumber | Where-Object { $_.DriveLetter } | Select-Object -Last 1).DriveLetter + ":\"
    
    # Backup current content
    $TempBackup = Join-Path $env:TEMP "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $TempBackup -Force | Out-Null
    Copy-Item -Path "$FullDirectory\*" -Destination $TempBackup -Recurse -Force
    
    # Move content to new limited drive and create junction
    Remove-Item -Path "$FullDirectory\*" -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "$TempBackup\*" -Destination $NewDrive -Recurse -Force
    
    # Remove old directory and create junction point
    cmd.exe /c "rmdir `"$FullDirectory`" 2>nul"
    cmd.exe /c "mklink /J `"$FullDirectory`" `"$NewDrive`""
    
    # Cleanup
    Remove-Item $TempBackup -Recurse -Force
    
    $NewSizeMB = [math]::Round((Get-ChildItem -Path $NewDrive -Recurse -Force | Measure-Object -Property Length -Sum).Sum / 1MB)
    $NewPercentage = [math]::Round(($NewSizeMB / $LimitMB) * 100)
    $FreedSpace = $SizeMB - $NewSizeMB
    
    Write-Host "=== Results ==="
    Write-Host "Files archived: $FileCount"
    Write-Host "New size: ${NewSizeMB}MB"
    Write-Host "New percentage: ${NewPercentage}%"
    Write-Host "Freed space: ${FreedSpace}MB"
    Write-Host "Folder now has HARD limit of ${LimitInput} - impossible to exceed!"
}
catch {
    Write-Error "Error creating VHD: $($_.Exception.Message)"
    exit 1
}