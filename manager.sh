#!/bin/bash

AUTO_YES=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interactive)
            INTERACTIVE=1
            shift
            ;;
        -y|--assume-yes)
            AUTO_YES=1
            shift
            ;;
        *)
            break
            ;;
    esac
done

#Some_functions-----
answer(){
    if [ $AUTO_YES -eq 1 ]; then
        echo "$1 [Y/n]: y (auto-confirmed)"
        return 0
    fi

    local message="$1"
    read -p "$message [Y/n]: " choice
    [[ -z "$choice" || "$choice" =~ ^[Yy]$ ]]
}

get_input() {
    local prompt="$1"
    local default="$2"
    local input

    read -p "$prompt [$default]: " input
    echo "${input:-$default}"
}

show_usage(){
    echo "=== Archiving manager ==="
    echo "Usage: $0 <directory> <limit in MB> <percentage threshold>"
    echo "Or: $0 -i (interactive mode)"
    echo "Or: $0 -y (auto confirm all prompts)"
    echo ""
    echo "Example: $0 /var/log 100 20"
}

setup_interactive() {
    echo "=== Archiving Manager - Interactive Setup ==="
    echo ""

    while true; do
        DIRECTORY=$(get_input "Enter directory to monitor" "$PWD")
        if [ -d "$DIRECTORY" ]; then
            break
        else
            echo "Error: Directory '$DIRECTORY' does not exist"
            if answer "Create directory?"; then
                mkdir -p "$DIRECTORY" && break
            fi
        fi
    done

    while true; do
        LIMIT=$(get_input "Enter size limit in MB" "100")
        if [[ "$LIMIT" =~ ^[0-9]+$ ]] && [ "$LIMIT" -gt 0 ]; then
            break
        else
            echo "Error: Limit must be a positive number"
        fi
    done

    # Get threshold
    while true; do
        N=$(get_input "Enter percentage threshold for archiving" "20")
        if [[ "$N" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "Error: Threshold must be a number"
        fi
    done

    echo ""
    echo "=== Configuration Summary ==="
    echo "Directory: $DIRECTORY"
    echo "Size limit: ${LIMIT}MB"
    echo "Archive threshold: ${N}% of limit"
    echo "Archive trigger: $((LIMIT * N / 100))MB"
    echo ""

    if answer "Proceed with this configuration?"; then
        echo "Starting..."
    else
        echo "Setup cancelled."
        exit 0
    fi
}

# Checking arguments
if [ $INTERACTIVE -eq 1 ]; then
    setup_interactive
elif [ $# -eq 3 ]; then
    DIRECTORY="$1"
    LIMIT="$2"
    N="$3"
elif [ $# -eq 0 ]; then
    show_usage
    exit 1
else
    show_usage
    exit 1
fi

BACKUP="backup"

FULL_DIRECTORY=$(realpath "$DIRECTORY")

# Checking directory existence
if [ ! -d "$FULL_DIRECTORY" ]; then
    echo "Error: Directory '$FULL_DIRECTORY' does not exist"
    exit 1
fi

if [ "$LIMIT" -eq 0 ]; then
    echo "Error: Limit cannot be zero"
    exit 1
fi

# Checking write permissions
if [ ! -w "$FULL_DIRECTORY" ]; then
    echo "Error: No write permission for directory '$FULL_DIRECTORY'"
    exit 1
fi

# SIZE
SIZE_MB=$(du -sm "$FULL_DIRECTORY" 2>/dev/null | tail -1 | cut -f1)
ARCHIVE_TRIGGER=$((LIMIT * N / 100))
echo "Directory size: ${SIZE_MB}MB"
echo "Archive trigger: ${ARCHIVE_TRIGGER}MB"

PERCENTAGE=$((SIZE_MB * 100 / LIMIT))
echo "CURRENT percentage: ${PERCENTAGE}% of limit"

#First scenary ------------------------------------------------------------
if [ $SIZE_MB -le $ARCHIVE_TRIGGER ]; then
    echo " Within threshold limits, no archiving needed"
    
    if answer "Apply hard folder size restriction of ${LIMIT}MB?"; then
        echo "Applying folder size restriction to prevent exceeding limit..."

        LOOP_FILE="/limited_${DIRECTORY##*/}.img"
            
        if mountpoint -q "$FULL_DIRECTORY"; then
            echo "Directory is already mounted, unmounting..."
            sudo umount "$FULL_DIRECTORY"
        fi
         
        if [ -f "$LOOP_FILE" ]; then
            if answer "Loop file $LOOP_FILE already exists. Overwrite?"; then
                sudo rm -f "$LOOP_FILE"
            else
                echo "Operation cancelled."
                exit 0
            fi
        fi
        
        # Create loop device with exact size limit
        sudo dd if=/dev/zero of="$LOOP_FILE" bs=1M count=$LIMIT 2>/dev/null
        sudo mkfs.ext4 -q "$LOOP_FILE"
       
        TEMP_BACKUP=$(mktemp -d)
        cp -r "$FULL_DIRECTORY"/* "$TEMP_BACKUP/" 2>/dev/null
        
        sudo rm -rf "$FULL_DIRECTORY"/*
        
        sudo mount -o loop "$LOOP_FILE" "$FULL_DIRECTORY"
        sudo chown $(whoami):$(whoami) "$FULL_DIRECTORY"
        
        # Restore content
        cp -r "$TEMP_BACKUP/"* "$FULL_DIRECTORY/" 2>/dev/null
        rm -rf "$TEMP_BACKUP"
        
        if answer "Add to /etc/fstab for automatic mounting?"; then
            echo "$LOOP_FILE $FULL_DIRECTORY ext4 loop,defaults 0 0" | sudo tee -a /etc/fstab
        fi
        
        echo "Folder now has hard limit of ${LIMIT}MB"
    else
        echo "Operation cancelled."
    fi
    exit 0
fi
#------------------------------------------------------------------------

# Second scenario - need archiving
echo "Size exceeds threshold, archiving required"

if answer "Start archiving old files?"; then
    # Create backup directory if it doesn't exist
    BACKUP_DIR="$FULL_DIRECTORY/$BACKUP"
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "Creating directory for <backup>"
        mkdir -p "$BACKUP_DIR"
    fi

    if [ ! -w "$BACKUP_DIR" ]; then
        echo "Error: No write permission for backup directory '$BACKUP_DIR'"
        exit 1
    fi

    # Second scenario ------------------------------------------------------
    ARCHIVED_COUNT=0
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ARCHIVE_NAME="$BACKUP_DIR/logs_backup_$TIMESTAMP.tar.gz"
    FILES_TO_ARCHIVE=()

    echo "Starting archiving process to reduce directory size..."

    INITIAL_SIZE=$SIZE_MB

    while [ $SIZE_MB -gt $ARCHIVE_TRIGGER ]; do
        # Find the oldest file
        OLDEST_FILE=$(find "$FULL_DIRECTORY" -maxdepth 1 -type f -not -path "*/$BACKUP/*" -printf '%T@ %p\n' 2>/dev/null | sort -n | head -n 1 | cut -d' ' -f2-)
        
        if [ -z "$OLDEST_FILE" ]; then
            echo "No more files found to archive"
            break
        fi

        if [ ! -f "$OLDEST_FILE" ]; then
            continue
        fi
        
        FILES_TO_ARCHIVE+=("$OLDEST_FILE")
        echo "Adding to archive: $(basename "$OLDEST_FILE")"
        
        # Recalculate size after adding this file to archive list
        SIZE_MB=$(du -sm "$FULL_DIRECTORY" | cut -f1)
        
        # If we've collected some files or size is still over limit, create archive
        if [ ${#FILES_TO_ARCHIVE[@]} -ge 5 ] || [ $SIZE_MB -le $ARCHIVE_TRIGGER ]; then
            if [ ${#FILES_TO_ARCHIVE[@]} -gt 0 ]; then
                echo "Creating archive with ${#FILES_TO_ARCHIVE[@]} files..."
            
                cd "$FULL_DIRECTORY" && tar -czf "$ARCHIVE_NAME" "${FILES_TO_ARCHIVE[@]##*/}" 2>/dev/null
                cd - > /dev/null
            
                echo "Removing archived files..."
                rm -rf "${FILES_TO_ARCHIVE[@]}"
            
                ARCHIVED_COUNT=$((ARCHIVED_COUNT + ${#FILES_TO_ARCHIVE[@]}))
                FILES_TO_ARCHIVE=()
            
                sync
                SIZE_MB=$(du -sm "$FULL_DIRECTORY" 2>/dev/null | tail -1 | cut -f1)
            
                echo "Current size after archiving: ${SIZE_MB}MB"
            
                # Update archive name for next batch
                TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                ARCHIVE_NAME="$BACKUP_DIR/logs_backup_$TIMESTAMP.tar.gz"
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

    echo "Archiving completed: $ARCHIVED_COUNT files archived"
else
    echo "Archiving cancelled."
    exit 0
fi

# Apply hard limit after archiving
if answer "Apply HARD folder size restriction of ${LIMIT}MB?"; then
    echo "Applying HARD folder size restriction..."
    SIZE_MB=$(du -sm "$FULL_DIRECTORY" | cut -f1)

    # Create loop directory
    echo "Creating loop device with hard limit of ${LIMIT}MB..."
    LOOP_FILE="/limited_${DIRECTORY##*/}.img"
    
    # Check if loop file already exists
    if [ -f "$LOOP_FILE" ]; then
        if answer "Loop file $LOOP_FILE already exists. Overwrite?"; then
            sudo rm -f "$LOOP_FILE"
        else
            echo "Operation cancelled."
            exit 0
        fi
    fi
    
    sudo dd if=/dev/zero of="$LOOP_FILE" bs=1M count=$LIMIT 2>/dev/null
    sudo mkfs.ext4 -q "$LOOP_FILE"

    # Backup current content
    TEMP_BACKUP=$(mktemp -d)
    cp -r "$FULL_DIRECTORY"/* "$TEMP_BACKUP/" 2>/dev/null

    sudo rm -rf "$FULL_DIRECTORY"/*

    # Mount limited filesystem
    sudo mount -o loop "$LOOP_FILE" "$FULL_DIRECTORY"
    sudo chown $(whoami):$(whoami) "$FULL_DIRECTORY"

    # Restore content
    cp -r "$TEMP_BACKUP/"* "$FULL_DIRECTORY/" 2>/dev/null
    rm -rf "$TEMP_BACKUP"

    # Add to fstab for persistence
    if answer "Add to /etc/fstab for automatic mounting?"; then
        echo "$LOOP_FILE $FULL_DIRECTORY ext4 loop,defaults 0 0" | sudo tee -a /etc/fstab
    fi

    NEW_SIZE_MB=$(du -sm "$FULL_DIRECTORY" | cut -f1)
    NEW_PERCENTAGE=$((NEW_SIZE_MB * 100 / LIMIT))
    FREED_SPACE=$((INITIAL_SIZE - NEW_SIZE_MB))

    echo "=== Results ==="
    echo "Files archived: $ARCHIVED_COUNT"
    echo "New size: ${NEW_SIZE_MB}MB"
    echo "New percentage: ${NEW_PERCENTAGE}%"
    echo "Freed space: ${FREED_SPACE}MB"
    echo "Folder now has HARD limit of ${LIMIT}MB - impossible to exceed!"
else
    echo "Hard limit setup cancelled."
fi
