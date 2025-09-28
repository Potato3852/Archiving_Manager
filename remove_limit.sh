#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

DIRECTORY="$1"
IMAGE_FILE="/limited_${DIRECTORY##*/}.img"

echo "=== Removing limits from $DIRECTORY ==="

# Check if directory is mounted as loop device
if mount | grep -q "$DIRECTORY"; then
    echo "1. Unmounting loop device..."
    sudo umount "$DIRECTORY"
    
    if [ $? -eq 0 ]; then
        echo "   Successfully unmounted"
    else
        echo "   Failed to unmount. Trying lazy unmount..."
        sudo umount -l "$DIRECTORY"
    fi
else
    echo "1. Directory is not mounted as loop device"
fi

# Remove from fstab
echo "2. Removing from /etc/fstab..."
if grep -q "$IMAGE_FILE" /etc/fstab; then
    sudo sed -i "\|$IMAGE_FILE|d" /etc/fstab
    echo "   Removed from fstab"
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

# Restore directory permissions if needed
echo "4. Restoring directory permissions..."
sudo chmod 755 "$DIRECTORY" 2>/dev/null
sudo chown $(whoami):$(whoami) "$DIRECTORY" 2>/dev/null

echo "=== Limit removal complete ==="
echo "Directory: $DIRECTORY is now back to normal"
