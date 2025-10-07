#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

DIRECTORY="$1"
# Получаем абсолютный путь
FULL_DIRECTORY=$(realpath "$DIRECTORY" 2>/dev/null)

if [ -z "$FULL_DIRECTORY" ]; then
    echo "Error: Directory '$DIRECTORY' not found or inaccessible"
    exit 1
fi

IMAGE_FILE="/limited_${DIRECTORY##*/}.img"

echo "=== Removing limits from $FULL_DIRECTORY ==="

# Более надежная проверка монтирования
echo "1. Checking if directory is mounted..."
MOUNT_POINT=$(mount | grep "$FULL_DIRECTORY" | awk '{print $3}')

if [ -n "$MOUNT_POINT" ]; then
    echo "   Directory is mounted as: $MOUNT_POINT"
    echo "   Unmounting loop device..."
    sudo umount "$FULL_DIRECTORY"
    
    if [ $? -eq 0 ]; then
        echo "   Successfully unmounted"
    else
        echo "   Failed to unmount. Trying lazy unmount..."
        sudo umount -l "$FULL_DIRECTORY"
        
        # Двойная проверка
        if mount | grep -q "$FULL_DIRECTORY"; then
            echo "   WARNING: Still mounted after lazy unmount!"
            echo "   You may need to check what's using it: sudo lsof $FULL_DIRECTORY"
        else
            echo "   Successfully unmounted with lazy option"
        fi
    fi
else
    echo "   Directory is not mounted"
fi

# Remove from fstab
echo "2. Removing from /etc/fstab..."
if sudo grep -q "$IMAGE_FILE" /etc/fstab; then
    sudo sed -i "\|$IMAGE_FILE|d" /etc/fstab
    echo "   Removed from fstab"
    
    # Принудительно обновляем systemd
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

# Restore directory permissions if needed
echo "4. Restoring directory permissions..."
sudo chmod 755 "$FULL_DIRECTORY" 2>/dev/null
sudo chown $(whoami):$(whoami) "$FULL_DIRECTORY" 2>/dev/null

echo "=== Limit removal complete ==="
echo "Directory: $FULL_DIRECTORY should now be removable"

# Финальная проверка
echo ""
echo "=== Verification ==="
if mount | grep -q "$FULL_DIRECTORY"; then
    echo "   WARNING: Directory is still mounted!"
    echo "   Try manual commands:"
    echo "   sudo umount -f $FULL_DIRECTORY"
    echo "   sudo umount -l $FULL_DIRECTORY"
else
    echo "Directory is successfully unmounted"
fi

if sudo grep -q "$IMAGE_FILE" /etc/fstab; then
    echo "WARNING: Entry still exists in fstab!"
else
    echo "fstab entry removed"
fi

if [ -f "$IMAGE_FILE" ]; then
    echo "WARNING: Image file still exists!"
else
    echo "Image file removed"
fi
