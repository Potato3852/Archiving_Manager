#!/bin/bash

# Checking numbers of arguments
if [ $# -ne 3 ]; then
    echo "Error: give 3 args in format <directory> <limit in MB> <percentage threshold>"
    exit 1
fi

DIRECTORY="$1"
LIMIT="$2"
N="$3"
BACKUP="backup"

# Cheking directory existance
if [ ! -d "$DIRECTORY" ]; then
    echo "Error: Directory '$DIRECTORY' does not exist"
    exit 1
fi

if [ "$LIMIT" -eq 0 ]; then
    echo "Error: Limit cannot be zero"
    exit 1
fi

# Cheling rules of status
if [ ! -w "$DIRECTORY" ]; then
    echo "Error: No write permission for directory '$DIRECTORY'"
    exit 1
fi

cd "$DIRECTORY" || {
    echo "Error: Cannot change to directory '$DIRECTORY'"
    exit 1
}

# SIZE of dir and percentage
SIZE_MB=$(du -sm . | cut -f1)
echo "Directory size: ${SIZE_MB}MB"

PERCENTAGE=$((SIZE_MB * 100 / LIMIT))
echo "CURRENT percentage: ${PERCENTAGE} of limit"

#First scenary ------------------------------------------------------------
if [ $PERCENTAGE -le $((100 + N)) ]; then
    echo " Within threshold limits, no archiving needed"
    echo "Applying folder size restriction to prevent exceeding limit..."
    
    # Create loop device with exact size limit
    sudo dd if=/dev/zero of="/limited_${DIRECTORY##*/}.img" bs=1M count=$LIMIT 2>/dev/null
    sudo mkfs.ext4 -q "/limited_${DIRECTORY##*/}.img"
    
    # backup
    TEMP_BACKUP=$(mktemp -d)
    cp -r ./* "$TEMP_BACKUP/" 2>/dev/null
    
    sudo mount -o loop "/limited_${DIRECTORY##*/}.img" "$DIRECTORY"
    sudo chown $(whoami):$(whoami) "$DIRECTORY"
    
    # Restore content
    cp -r "$TEMP_BACKUP/"* "$DIRECTORY/" 2>/dev/null
    rm -rf "$TEMP_BACKUP"
    
    echo "/limited_${DIRECTORY##*/}.img $DIRECTORY ext4 loop,defaults 0 0" | sudo tee -a /etc/fstab
    
    echo "Folder now has hard limit of ${LIMIT}MB"
    exit 0
fi
#------------------------------------------------------------------------

# Create backup directory if it doesn't exist
if [ ! -d "$BACKUP" ]; then
    echo "Creating directory for <backup>"
    mkdir -p "$BACKUP"
fi

if [ ! -w "$BACKUP" ]; then
    echo "Error: No write permission for backup directory '$BACKUP'"
    exit 1
fi

# Second sccenary ------------------------------------------------------
ARCHIVED_COUNT=0
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE_NAME="$BACKUP/logs_backup_$TIMESTAMP.tar.gz"
FILES_TO_ARCHIVE=()

echo "Starting archiving process to reduce directory size..."

while [ $PERCENTAGE -gt $((100 + N)) ]; do
    # Find the oldest file
    OLDEST_FILE=$(find "$DIRECTORY" -maxdepth 1 -type f -not -path "*/$BACKUP/*" -printf '%T@ %p\n' | sort -n | head -n 1 | cut -d' ' -f2-)
    
    if [ -z "$OLDEST_FILE" ]; then
        echo "No more files found to archive"
        break
    fi
    
    FILES_TO_ARCHIVE+=("$OLDEST_FILE")
    echo "Adding to archive: $OLDEST_FILE"
    
    # Recalculate size after adding this file to archive list
    SIZE_MB=$(du -sm . | cut -f1)
    PERCENTAGE=$((SIZE_MB * 100 / LIMIT))
    
    # If we've collected some files or size is still over limit, create archive
    if [ ${#FILES_TO_ARCHIVE[@]} -ge 5 ] || [ $PERCENTAGE -le $((100 + N)) ]; then
        if [ ${#FILES_TO_ARCHIVE[@]} -gt 0 ]; then
            echo "Creating archive with ${#FILES_TO_ARCHIVE[@]} files..."
            tar -czf "$ARCHIVE_NAME" "${FILES_TO_ARCHIVE[@]}"
            
            echo "Removing archived files..."
            rm -rf "${FILES_TO_ARCHIVE[@]}"
            
            ARCHIVED_COUNT=$((ARCHIVED_COUNT + ${#FILES_TO_ARCHIVE[@]}))
            FILES_TO_ARCHIVE=()
            
            # Update archive name for next batch if needed
            TIMESTAMP=$(date +%Y%m%d_%H%M%S)
            ARCHIVE_NAME="$BACKUP/logs_backup_$TIMESTAMP.tar.gz"
        fi
    fi
done
#--------------------------------------------------------------------


if [ ${#FILES_TO_ARCHIVE[@]} -gt 0 ]; then
    echo "Creating final archive with ${#FILES_TO_ARCHIVE[@]} files..."
    tar -czf "$ARCHIVE_NAME" "${FILES_TO_ARCHIVE[@]}"
    echo "Removing archived files..."
    rm -rf "${FILES_TO_ARCHIVE[@]}"
    ARCHIVED_COUNT=$((ARCHIVED_COUNT + ${#FILES_TO_ARCHIVE[@]}))
fi

# HARD
echo "Applying HARD folder size restriction..."
SIZE_MB=$(du -sm . | cut -f1)

# Create loop directory
echo "Creating loop device with hard limit of ${LIMIT}MB..."
sudo dd if=/dev/zero of="/limited_${DIRECTORY##*/}.img" bs=1M count=$LIMIT 2>/dev/null
sudo mkfs.ext4 -q "/limited_${DIRECTORY##*/}.img"

# Backup current content
TEMP_BACKUP=$(mktemp -d)
cp -r ./* "$TEMP_BACKUP/" 2>/dev/null

# Mount limited filesystem
sudo mount -o loop "/limited_${DIRECTORY##*/}.img" "$DIRECTORY"
sudo chown $(whoami):$(whoami) "$DIRECTORY"

# Restore content
cp -r "$TEMP_BACKUP/"* "$DIRECTORY/" 2>/dev/null
rm -rf "$TEMP_BACKUP"

# Add to fstab for persistence
echo "/limited_${DIRECTORY##*/}.img $DIRECTORY ext4 loop,defaults 0 0" | sudo tee -a /etc/fstab

NEW_SIZE_MB=$(du -sm . | cut -f1)
NEW_PERCENTAGE=$((NEW_SIZE_MB * 100 / LIMIT))
FREED_SPACE=$((SIZE_MB - NEW_SIZE_MB))

echo "=== Results ==="
echo "Files archived: $ARCHIVED_COUNT"
echo "New size: ${NEW_SIZE_MB}MB"
echo "New percentage: ${NEW_PERCENTAGE}%"
echo "Freed space: ${FREED_SPACE}MB"
echo "Folder now has HARD limit of ${LIMIT}MB - impossible to exceed!"
