# remove_limit.ps1
param(
    [string]$Directory
)

if (-not $Directory) {
    Write-Error "Error: Directory path is required"
    Write-Host "Usage: .\remove_limit.ps1 <directory>"
    exit 1
}

if (-not (Test-Path $Directory -PathType Container)) {
    Write-Error "Error: Directory '$Directory' does not exist"
    exit 1
}

$FullDirectory = (Resolve-Path $Directory).Path

# Check if it's a junction point
$dirInfo = Get-Item $FullDirectory
if ($dirInfo.Attributes -match "ReparsePoint") {
    Write-Host "Found junction point, removing link..."
    
    # Get the target of the junction
    $junctionTarget = cmd.exe /c "dir /A:L `"$FullDirectory`" 2>nul" | 
                     Where-Object { $_ -match "\[(.+)\]" } | 
                     ForEach-Object { $matches[1] }
    
    if ($junctionTarget) {
        Write-Host "Junction points to: $junctionTarget"
        
        # Remove the junction point
        cmd.exe /c "rmdir `"$FullDirectory`" 2>nul"
        
        # Copy content back from VHD to original directory
        if (Test-Path $junctionTarget) {
            Write-Host "Restoring content from VHD to original directory..."
            Copy-Item -Path "$junctionTarget\*" -Destination $FullDirectory -Recurse -Force
        }
        
        # Try to unmount and remove VHD
        $vhdPath = "C:\limited_$(Split-Path $FullDirectory -Leaf).vhdx"
        if (Test-Path $vhdPath) {
            Write-Host "Removing VHD file: $vhdPath"
            
            # Get disk number from VHD
            try {
                $vhdInfo = Get-VHD -Path $vhdPath -ErrorAction SilentlyContinue
                if ($vhdInfo) {
                    # Dismount VHD
                    Dismount-VHD -Path $vhdPath -ErrorAction SilentlyContinue
                }
                Remove-Item $vhdPath -Force -ErrorAction SilentlyContinue
                Write-Host "VHD removed successfully"
            }
            catch {
                Write-Warning "Could not remove VHD: $($_.Exception.Message)"
            }
        }
        
        Write-Host "Limit removed successfully from $FullDirectory"
    }
} else {
    Write-Host "Directory is not a limited junction point"
    Write-Host "No limits to remove from $FullDirectory"
}