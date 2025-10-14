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

to_megabytes() {
    local value=$1

    value=$(echo "$value" | tr -d ' ')
    
    local num=$(echo "$value" | grep -oE '^[0-9]+(\.[0-9]+)?')
    local unit=$(echo "$value" | grep -oE '[a-zA-Z]+$' | tr '[:upper:]' '[:lower:]')
    
    case $unit in 
        "k"|"kb") echo "$num / 1024" | bc -l ;;
        "m"|"mb") echo "$num" ;;
        "g"|"gb") echo "$num * 1024" | bc -l ;;
        "t"|"tb") echo "$num * 1024 * 1024" | bc -l ;;
        *) echo "$num" ;; 
    esac
}

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
    echo "Usage: $0 <directory> <limit> <percentage threshold>"
    echo "Limit can be in KB, MB, GB, TB (e.g., 1G, 500M, 2.5GB)"
    echo "Or: $0 -i (interactive mode)"
    echo "Or: $0 -y (auto confirm all prompts)"
    echo ""
    echo "Example: $0 /var/log 1G 20"
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
        LIMIT_INPUT=$(get_input "Enter size limit (e.g., 1G, 500M, 2.5GB)" "1G")
        LIMIT_MB=$(to_megabytes "$LIMIT_INPUT")
        LIMIT_MB=${LIMIT_MB%.*}
        
        if [[ "$LIMIT_MB" =~ ^[0-9]+$ ]]; then
            break
        fi
    done

    # Get threshold
    while true; do
        N=$(get_input "Enter percentage threshold for archiving" "20")
        if [[ "$N" =~ ^[0-9]+$ ]] && [ "$N" -le 100 ]; then
            break
        else
            echo "Error: Threshold must be a number between 0-100"
        fi
    done

    echo ""
    echo "=== Configuration Summary ==="
    echo "Directory: $DIRECTORY"
    echo "Size limit: ${LIMIT_INPUT} (${LIMIT_MB}MB)"
    echo "Archive threshold: ${N}% of limit"
    echo "Archive trigger: $((LIMIT_MB * N / 100))MB"
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
    LIMIT_INPUT="$2"
    N="$3"
    
    # Convert limit to MB
    LIMIT_MB=$(to_megabytes "$LIMIT_INPUT")
    LIMIT_MB=${LIMIT_MB%.*}
    
elif [ $# -eq 0 ]; then
    show_usage
    exit 1
else
    show_usage
    exit 1
fi

BACKUP_DIR="$(dirname "$(realpath "$DIRECTORY")")/$(basename "$DIRECTORY")_backups"

FULL_DIRECTORY=$(realpath "$DIRECTORY")

# Checking directory existence
if [ ! -d "$FULL_DIRECTORY" ]; then
    echo "Error: Directory '$FULL_DIRECTORY' does not exist"
    exit 1
fi

# Checking write permissions
if [ ! -w "$FULL_DIRECTORY" ]; then
    echo "Error: No write permission for directory '$FULL_DIRECTORY'"
    exit 1
fi

# SIZE
SIZE_MB=$(du -sm "$FULL_DIRECTORY" 2>/dev/null | tail -1 | cut -f1)
ARCHIVE_TRIGGER=$((LIMIT_MB * N / 100))
echo "Directory size: ${SIZE_MB}MB"
echo "Limit: ${LIMIT_MB}MB"
echo "Archive trigger: ${ARCHIVE_TRIGGER}MB"

PERCENTAGE=$((SIZE_MB * 100 / LIMIT_MB))
echo "CURRENT percentage: ${PERCENTAGE}% of limit"

#First scenario ------------------------------------------------------------
if [ $SIZE_MB -le $ARCHIVE_TRIGGER ]; then
    echo "Within threshold limits, no archiving needed"
    
    if answer "Apply hard folder size restriction of ${LIMIT_INPUT}?"; then
        echo "Applying folder size restriction to prevent exceeding limit..."

        LOOP_FILE="/limited_${DIRECTORY##*/}.img"
            
        if mountpoint -q "$FULL_DIRECTORY"; then
            echo "Directory is already mounted, unmounting..."
            umount "$FULL_DIRECTORY"
        fi
         
        if [ -f "$LOOP_FILE" ]; then
            if answer "Loop file $LOOP_FILE already exists. Overwrite?"; then
                rm -f "$LOOP_FILE"
            else
                echo "Operation cancelled."
                exit 0
            fi
        fi
        
        # Create loop device with exact size limit
        dd if=/dev/zero of="$LOOP_FILE" bs=1M count=$LIMIT_MB 2>/dev/null
        mkfs.ext4 -q "$LOOP_FILE"
       
        TEMP_BACKUP=$(mktemp -d)
        cp -r "$FULL_DIRECTORY"/* "$TEMP_BACKUP/" 2>/dev/null
        
        rm -rf "$FULL_DIRECTORY"/*
        
	mount -o loop,uid=$(id -u),gid=$(id -g) "$LOOP_FILE" "$FULL_DIRECTORY"
        chown $(whoami):$(whoami) "$FULL_DIRECTORY"
        
        # Restore content
        cp -r "$TEMP_BACKUP/"* "$FULL_DIRECTORY/" 2>/dev/null
        rm -rf "$TEMP_BACKUP"
        
        if answer "Add to /etc/fstab for automatic mounting?"; then
            echo "$LOOP_FILE $FULL_DIRECTORY ext4 loop,defaults 0 0" | tee -a /etc/fstab
        fi
        
        echo "Folder now has hard limit of ${LIMIT_INPUT}"
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
    mkdir -p "$BACKUP_DIR"

    if [ ! -w "$BACKUP_DIR" ]; then
        echo "Error: No write permission for backup directory '$BACKUP_DIR'"
        exit 1
    fi

    echo "WARNING: Usage exceeds $N% limit! Calculating files to archive..."
    
    space_to_free=$((SIZE_MB - ARCHIVE_TRIGGER))
    echo "Need to free approximately $space_to_free MB"
    
    file_list=$(mktemp)
    find "$FULL_DIRECTORY" -maxdepth 1 -type f -not -path "$BACKUP_DIR/*" -printf '%T@ %s %p\0' 2>/dev/null | \
    sort -zn > "$file_list"
    
    if [ ! -s "$file_list" ]; then
        echo "No files found to archive."
        rm -f "$file_list"
        exit 0
    fi
    
    files_to_archive=$(mktemp)
    current_freed=0
    file_count=0
    
    while IFS= read -r -d '' line; do
        file_timestamp=$(echo "$line" | cut -d' ' -f1)
        file_size=$(echo "$line" | cut -d' ' -f2)
        file_path=$(echo "$line" | cut -d' ' -f3-)
        
        file_size_mb=$((file_size / 1024 / 1024))
        
        if [ $current_freed -lt $space_to_free ] || [ $file_count -eq 0 ]; then
            echo -n -e "$file_path\0" >> "$files_to_archive"
            current_freed=$((current_freed + file_size_mb))
            file_count=$((file_count + 1))
        else
            break
        fi
    done < "$file_list"
    
    rm -f "$file_list"
    
    if [ $file_count -eq 0 ]; then
        echo "No files selected for archiving."
        rm -f "$files_to_archive"
        exit 0
    fi
    
    echo "Selected $file_count files to archive (~$current_freed MB)"
    
    if answer "Show files that will be archived?"; then
        echo "Files to be archived:"
        while IFS= read -r -d '' file; do
            if [ -n "$file" ]; then
                echo "  $file"
            fi
        done < "$files_to_archive"
    fi
    
    timestamp=$(date +%Y%m%d_%H%M%S)
    archive_name="${BACKUP_DIR}/backup_${timestamp}.tar.gz"
    
    echo "Creating archive: $archive_name"
    
    if tar -czf "$archive_name" --null -T "$files_to_archive" 2>/dev/null; then
        archive_size=$(du -h "$archive_name" | cut -f1)
        echo "Archive created successfully: $archive_name"
        echo "Archive size: $archive_size"
        
        echo "Removing original files..."
        removed_count=0
        while IFS= read -r -d '' file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                if rm -f "$file"; then
                    removed_count=$((removed_count + 1))
                else
                    echo "Warning: Could not remove $file"
                fi
            fi
        done < "$files_to_archive"
        
        echo "Original files removed: $removed_count files"
        
        new_size=$(du -sm "$FULL_DIRECTORY" 2>/dev/null | tail -1 | cut -f1)
        new_ratio=$((new_size * 100 / LIMIT_MB))
        
        echo "Archiving completed:"
        echo "- Original size: $SIZE_MB MB"
        echo "- New size: $new_size MB"
        echo "- New fill ratio: $new_ratio%"
        echo "- Files archived: $file_count"
        echo "- Approximate space freed: $current_freed MB"
        
        if [ $new_size -le $ARCHIVE_TRIGGER ]; then
            echo "SUCCESS: Directory size is now below archive threshold!"
        else
            echo "WARNING: Directory size still exceeds threshold. Consider running script again."
        fi
        
    else
        echo "Error creating archive!"
        rm -f "$files_to_archive"
        exit 1
    fi
    
    rm -f "$files_to_archive"
    
else
    echo "Archiving cancelled."
    exit 0
fi

# Apply hard limit after archiving
if answer "Apply HARD folder size restriction of ${LIMIT_INPUT}?"; then
    echo "Applying HARD folder size restriction..."
    
    # Create loop directory
    echo "Creating loop device with hard limit of ${LIMIT_INPUT}..."
    LOOP_FILE="/limited_${DIRECTORY##*/}.img"
    
    # Check if loop file already exists
    if [ -f "$LOOP_FILE" ]; then
        if answer "Loop file $LOOP_FILE already exists. Overwrite?"; then
            rm -f "$LOOP_FILE"
        else
            echo "Operation cancelled."
            exit 0
        fi
    fi
    
    dd if=/dev/zero of="$LOOP_FILE" bs=1M count=$LIMIT_MB 2>/dev/null
    mkfs.ext4 -q "$LOOP_FILE"

    # Backup current content
    TEMP_BACKUP=$(mktemp -d)
    cp -r "$FULL_DIRECTORY"/* "$TEMP_BACKUP/" 2>/dev/null

    rm -rf "$FULL_DIRECTORY"/*

    # Mount limited filesystem
    mount -o loop "$LOOP_FILE" "$FULL_DIRECTORY"
    chown $(whoami):$(whoami) "$FULL_DIRECTORY"

    # Restore content
    cp -r "$TEMP_BACKUP/"* "$FULL_DIRECTORY/" 2>/dev/null
    rm -rf "$TEMP_BACKUP"

    # Add to fstab for persistence
    if answer "Add to /etc/fstab for automatic mounting?"; then
        echo "$LOOP_FILE $FULL_DIRECTORY ext4 loop,defaults 0 0" | tee -a /etc/fstab
    fi

    NEW_SIZE_MB=$(du -sm "$FULL_DIRECTORY" | cut -f1)
    NEW_PERCENTAGE=$((NEW_SIZE_MB * 100 / LIMIT_MB))
    FREED_SPACE=$((SIZE_MB - NEW_SIZE_MB))

    echo "=== Results ==="
    echo "Files archived: $file_count"
    echo "New size: ${NEW_SIZE_MB}MB"
    echo "New percentage: ${NEW_PERCENTAGE}%"
    echo "Freed space: ${FREED_SPACE}MB"
    echo "Folder now has HARD limit of ${LIMIT_INPUT} - impossible to exceed!"
else
    echo "Hard limit setup cancelled."
fi
