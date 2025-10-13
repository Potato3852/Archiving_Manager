# Archiving_Manager
A cross-platform solution for automatic directory archiving when storage limits are exceeded.
Contains both Linux bash script and Windows batch script versions.
## Overview

!!!test.sh is not working now. Please wait for the update!!!

This project provides two scripts that monitor directory size and automatically archive the oldest files when a specified storage limit is exceeded:

- **Linux version**: `manager.sh` (bash script)
- **Windows version**: `Windows_manager.bat` (batch script)
- **Remove_new_rules**: `remove_limit.sh` (bash script) it will help you to remove the current folder size limit.(on Windows just use another script)

## For Beginners (No Git Experience)

### How to download and use these scripts:

#### Method 1: Direct Download (Easiest)
1. **Go to the GitHub repository**: 
   - Open https://github.com/Potato3852/Archiving_Manager
   - Click the green "Code" button
   - Select "Download ZIP"

2. **Extract the files**:
   - Find the downloaded ZIP file (usually in "Downloads" folder)
   - Right-click and select "Extract All"
   - Choose where to extract (e.g., `C:\ArchiveManager` or `/home/user/ArchiveManager`)

3. **Place scripts in desired location**:
   - Copy the script you need to your target directory
   - For Linux: `archive_manager.sh`
   - For Windows: `archive_manager.bat`

#### Method 2: Using Git (Recommended)
1. **Install Git first**:
   - Windows: Download from https://git-scm.com/
   - Linux: `sudo apt install git` (Ubuntu/Debian) or `sudo yum install git` (CentOS/RHEL)

2. **Open command line**:
   - Windows: Press Win+R, type `cmd`, press Enter
   - Linux: Open Terminal

3. **Clone repository**:
   ```bash
   git clone https://github.com/Potato3852/Archiving_Manager.git
   cd Archiving_Manager

4. **Using**:
   ```bash
   ./manager.sh <limit> <N percentages>
   or
   ./manager.sh -i
