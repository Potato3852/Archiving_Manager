#!/bin/bash
# quick_test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="/tmp/quick_test"

echo "=== Подготовка теста ==="
mkdir -p "$TEST_DIR"
cd "$TEST_DIR" || exit 1

# Создаем несколько тестовых файлов с бОльшим размером
for i in {1..5}; do
    # Создаем файлы побольше (по 200KB каждый)
    dd if=/dev/urandom of="file$i.log" bs=10MB count=1 status=none
    echo "Это тестовый лог файл $i" >> "file$i.log"
done

echo "Создано 5 тестовых файлов"
ls -la
echo "Общий размер: $(du -sh . | cut -f1)"

# Запускаем manager.sh с лимитом 0 (гарантированное превышение)
echo -e "\n=== Запуск manager.sh ==="
"$SCRIPT_DIR/manager.sh" "$TEST_DIR" 20 3

echo -e "\n=== Результаты ==="
echo "Файлы в основной директории:"
ls -la

echo -e "\nФайлы в backup директории:"
if [ -d "backup" ]; then
    ls -la backup/
    echo -e "\nСодержимое архива (если создан):"
    ARCHIVE=$(find backup -name "*.tar.gz" | head -1)
    if [ -n "$ARCHIVE" ]; then
        tar -tzf "$ARCHIVE"
    else
        echo "Архив не найден"
    fi
else
    echo "Backup директория не создана"
fi

# Очистка
echo -e "\n=== Очистка ==="
cd /tmp && rm -rf "$TEST_DIR"
echo "Тестовая директория удалена"
