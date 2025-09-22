#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TEST_COUNT=0
PASSED_COUNT=0
FAILED_COUNT=0

echo_test() {
    echo -e "${YELLOW}TEST: $1${NC}"
    ((TEST_COUNT++))
}

echo_pass() {
    echo -e "${GREEN}PASS: $1${NC}"
    ((PASSED_COUNT++))
}

echo_fail() {
    echo -e "${RED}FAIL: $1${NC}"
    ((FAILED_COUNT++))
}

# Тест 1: Проверка использования (без аргументов)
echo_test "Testing error message (no arguments)"
output=$(bash manager.sh 2>&1)
if echo "$output" | grep -q "Error: give 4 args"; then
    echo_pass "Error message displayed correctly"
else
    echo_fail "Error message not displayed. Got: $output"
fi

# Тест 2: Создание тестовой среды
echo_test "Creating test environment"
TEST_DIR=$(mktemp -d)
LOG_DIR="$TEST_DIR/test_logs"
mkdir -p "$LOG_DIR"

# Создаем тестовые файлы с разными датами
for i in {1..5}; do
    touch -d "$i days ago" "$LOG_DIR/file$i.log"
    echo "This is test file $i" > "$LOG_DIR/file$i.log"
done

if [ -d "$LOG_DIR" ] && [ $(ls "$LOG_DIR" | wc -l) -eq 5 ]; then
    echo_pass "Test environment created successfully"
else
    echo_fail "Failed to create test environment"
fi

# Тест 3: Запуск скрипта с превышением лимита более чем на N%
echo_test "Running script with exceeded limit (should trigger archiving)"
# Создаем файлы так, чтобы размер превысил лимит более чем на N%
dd if=/dev/zero of="$LOG_DIR/large_file1.log" bs=1M count=2 2>/dev/null
dd if=/dev/zero of="$LOG_DIR/large_file2.log" bs=1M count=2 2>/dev/null

# Лимит 1MB, текущий размер ~4MB + файлы = превышение более чем на 15%
output=$(bash manager.sh "$LOG_DIR" 1 15 2 2>&1)

# Проверяем, что архив создан
if [ -d "$LOG_DIR/backup" ] && [ $(find "$LOG_DIR/backup" -name "*.tar.gz" | wc -l) -gt 0 ]; then
    echo_pass "Archive created successfully"
else
    echo_fail "Archive not created. Output: $output"
fi

# Тест 4: Запуск скрипта в пределах лимита + N%
echo_test "Running script within limit + threshold (should not trigger archiving)"
# Создаем чистую директорию для этого теста
CLEAN_DIR=$(mktemp -d)
mkdir -p "$CLEAN_DIR/logs"
touch "$CLEAN_DIR/logs/file1.log"
echo "small file" > "$CLEAN_DIR/logs/file1.log"

# Лимит 100MB, текущий размер ~0MB, N=15% - не должно архивировать
output=$(bash manager.sh "$CLEAN_DIR/logs" 100 15 2 2>&1)

if echo "$output" | grep -q "Within threshold limits"; then
    echo_pass "Script correctly identified usage within limits"
else
    echo_fail "Script did not correctly identify usage within limits. Output: $output"
fi

rm -rf "$CLEAN_DIR"

# Тест 5: Проверка превышения ровно на порог (не должно архивировать)
echo_test "Testing exact threshold (should not archive)"
THRESH_DIR=$(mktemp -d)
mkdir -p "$THRESH_DIR/logs"
# Создаем размер примерно 115MB при лимите 100MB и N=15 (ровно порог)
dd if=/dev/zero of="$THRESH_DIR/logs/file1.log" bs=1M count=115 2>/dev/null

output=$(bash manager.sh "$THRESH_DIR/logs" 100 15 2 2>&1)

if echo "$output" | grep -q "Within threshold limits"; then
    echo_pass "Script correctly handled exact threshold"
else
    echo_fail "Script failed at exact threshold. Output: $output"
fi

rm -rf "$THRESH_DIR"

# Тест 6: Проверка обработки несуществующей директории
echo_test "Testing non-existent directory handling"
output=$(bash manager.sh "/invalid/path/that/doesnt/exist" 10 15 2 2>&1)

if echo "$output" | grep -q "Error: Directory"; then
    echo_pass "Script correctly handled non-existent directory"
else
    echo_fail "Script did not handle non-existent directory correctly. Output: $output"
fi

# Очистка
rm -rf "$TEST_DIR"

# Итоги
echo
echo "=== TEST RESULTS ==="
echo "Total tests: $TEST_COUNT"
echo -e "${GREEN}Passed: $PASSED_COUNT${NC}"
echo -e "${RED}Failed: $FAILED_COUNT${NC}"

if [ $FAILED_COUNT -eq 0 ]; then
    echo -e "${GREEN}All tests passed! 🎉${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed! ❌${NC}"
    exit 1
fi
