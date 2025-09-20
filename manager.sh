#!/bin/bash

# Проверка количества аргументов
if [ $# -ne 3 ]; then
    echo "Error: give 3 args in format <directory> <limit in MB> <numbers of zip files>"
    exit 1
fi

DIRECTORY="$1"
LIMIT="$2"
M="$3"
BACKUP="backup"

# Проверка существования директории
if [ ! -d "$DIRECTORY" ]; then
    echo "Error: Directory '$DIRECTORY' does not exist"
    exit 1
fi

if ! [[ "$M" =~ ^[0-9]+$ ]]; then
    echo "Error: Number of files to archive must be a positive integer"
    exit 1
fi

if [ "$LIMIT" -eq 0 ]; then
    echo "Error: Limit cannot be zero"
    exit 1
fi

# Проверка прав доступа
if [ ! -w "$DIRECTORY" ]; then
    echo "Error: No write permission for directory '$DIRECTORY'"
    exit 1
fi

cd "$DIRECTORY" || {
    echo "Error: Cannot change to directory '$DIRECTORY'"
    exit 1
}

# Посчитаем и выведем размер директории в процентах от порога
SIZE_MB=$(du -sm . | cut -f1)
echo "Directory size: ${SIZE_MB}MB"

PERCENTAGE=$((SIZE_MB * 100 / LIMIT))
echo "CURRENT percentage: ${PERCENTAGE} of limit"

if [ $PERCENTAGE -le 100 ]; then
    echo " Within threshold limits, no archiving needed"
    exit 0
fi

# Найдем M самых старых файлов в директории
OLDEST_FILES=()
while IFS= read -r -d '' file; do
    OLDEST_FILES+=("$file")
done < <(find "$DIRECTORY" -maxdepth 1 -type f -printf '%T@ %p\0' | sort -nz | head -z -n "$M" | cut -z -d' ' -f2-)

if [ -z "$OLDEST_FILES" ]; then
    echo "No files found to archive"
    exit 0
fi

echo "Files to archive:"
echo "${OLDEST_FILES[@]}"

if [ ! -d "$BACKUP" ]; then
    echo "Creating directory for <backup>"
    mkdir -p "$BACKUP"

if [ ! -w "$BACKUP" ]; then
    echo "Error: No write permission for backup directory '$BACKUP'"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE_NAME="$BACKUP/logs_backup_$TIMESTAMP.tar.gz"

echo "Creating archives $ARCHIVE_NAME"
tar -czf "$ARCHIVE_NAME" "${OLDEST_FILES[@]}"

echo "Removing old files..."
rm -rf "${OLDEST_FILES[@]}

NEW_SIZE_MB=$(du -sm . | cut -f1)
NEW_PERCENTAGE=$((NEW_SIZE_MB * 100 / LIMIT))
FREED_SPACE=$((SIZE_MB - NEW_SIZE_MB))

echo "=== Results ==="
echo "New size: ${NEW_SIZE_MB}MB"
echo "New percentage: ${NEW_PERCENTAGE}%"
echo "Freed space: ${FREED_SPACE}MB"
echo "Archive created: $ARCHIVE_NAME"
