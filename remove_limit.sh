#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

DIRECTORY="$1"

FULL_DIRECTORY=$(realpath "$DIRECTORY" 2>/dev/null)

if [ -z "$FULL_DIRECTORY" ]; then
    echo "Error: Directory '$DIRECTORY' not found or inaccessible"
    exit 1
fi

IMAGE_FILE="/limited_${DIRECTORY##*/}.img"

echo "=== Removing limits from $FULL_DIRECTORY ==="

CURRENT_USER=$(whoami)
CURRENT_GROUP=$(id -gn)

echo "1. Checking if directory is mounted..."
MOUNT_POINT=$(mount | grep "$FULL_DIRECTORY" | awk '{print $3}')

if [ -n "$MOUNT_POINT" ]; then
    echo "   Directory is mounted as: $MOUNT_POINT"
    
    echo "   Backing up content from loop device..."
    TEMP_BACKUP=$(mktemp -d)
    cp -r "$FULL_DIRECTORY"/* "$TEMP_BACKUP/" 2>/dev/null
    
    echo "   Unmounting loop device..."
    sudo umount "$FULL_DIRECTORY"
    
    if [ $? -eq 0 ]; then
        echo "   Successfully unmounted"
    else
        echo "   Failed to unmount. Trying lazy unmount..."
        sudo umount -l "$FULL_DIRECTORY"
    fi
    
    echo "   Restoring files to original directory..."
    rm -rf "$FULL_DIRECTORY"/* 2>/dev/null
    cp -r "$TEMP_BACKUP"/* "$FULL_DIRECTORY/" 2>/dev/null
    
    echo "   Restoring permissions..."
    sudo chown -R $CURRENT_USER:$CURRENT_GROUP "$FULL_DIRECTORY"
    sudo chmod -R 755 "$FULL_DIRECTORY"
    
    rm -rf "$TEMP_BACKUP"
    
else
    echo "   Directory is not mounted"
    
    if [ -f "$IMAGE_FILE" ]; then
        echo "   Found image file, mounting to restore content..."
        TEMP_MOUNT=$(mktemp -d)
        
        if sudo mount -o loop "$IMAGE_FILE" "$TEMP_MOUNT" 2>/dev/null; then
            echo "   Copying content from image file..."
            rm -rf "$FULL_DIRECTORY"/* 2>/dev/null
            cp -r "$TEMP_MOUNT"/* "$FULL_DIRECTORY/" 2>/dev/null
            
            sudo chown -R $CURRENT_USER:$CURRENT_GROUP "$FULL_DIRECTORY"
            sudo chmod -R 755 "$FULL_DIRECTORY"
            
            sudo umount "$TEMP_MOUNT"
            echo "   Content restored from image file"
        else
            echo "   Could not mount image file"
        fi
        
        rm -rf "$TEMP_MOUNT"
    fi
fi

# Remove from fstab
echo "2. Removing from /etc/fstab..."
if sudo grep -q "$IMAGE_FILE" /etc/fstab; then
    sudo sed -i "\|$IMAGE_FILE|d" /etc/fstab
    echo "   Removed from fstab"
    
    if command -v systemctl >/dev/null 2>&1; then
        echo "   Reloading systemd..."
        sudo systemctl daemon-reload
    fi
else
    echo "   No fstab entry found"
fi

# Remove image file
echo "3. Removing image file..."
if [ -f "$IMAGE_FILE" ]; then
    sudo rm -f "$IMAGE_FILE"
    echo "   Removed $IMAGE_FILE"
else
    echo "   Image file not found: $IMAGE_FILE"
fi

# Final permission restoration
echo "4. Final permissions restoration..."
sudo chown -R $CURRENT_USER:$CURRENT_GROUP "$FULL_DIRECTORY" 2>/dev/null
sudo find "$FULL_DIRECTORY" -type f -exec chmod 644 {} \; 2>/dev/null
sudo find "$FULL_DIRECTORY" -type d -exec chmod 755 {} \; 2>/dev/null

echo "=== Limit removal complete ==="
echo "Directory: $FULL_DIRECTORY should now be accessible"

echo ""
echo "=== Verification ==="
if mount | grep -q "$FULL_DIRECTORY"; then
    echo "   WARNING: Directory is still mounted!"
else
    echo "    Directory is successfully unmounted"
fi

if sudo grep -q "$IMAGE_FILE" /etc/fstab; then
    echo "   WARNING: Entry still exists in fstab!"
else
    echo "    fstab entry removed"
fi

if [ -f "$IMAGE_FILE" ]; then
    echo "   WARNING: Image file still exists!"
else
    echo "    Image file removed"
fi

echo "     Current permissions:"
echo "     Owner: $(stat -c "%U:%G" "$FULL_DIRECTORY" 2>/dev/null)"
echo "     Perms: $(stat -c "%a" "$FULL_DIRECTORY" 2>/dev/null)"
echo "     Files: $(find "$FULL_DIRECTORY" -type f 2>/dev/null | wc -l)"
