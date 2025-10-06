#!/bin/bash

TEST_COUNT=0
PASSED_COUNT=0
FAILED_COUNT=0

echo_test() {
    echo "TEST: $1"
    ((TEST_COUNT++))
}

echo_pass() {
    echo "PASS: $1"
    ((PASSED_COUNT++))
}

echo_fail() {
    echo "FAIL: $1"
    ((FAILED_COUNT++))
}

# Test 1: Check usage message (wrong number of arguments)
echo_test "Testing usage message (wrong number of arguments)"
output=$(bash manager.sh 2>&1)

if echo "$output" | grep -q "Usage:"; then
    echo_pass "Usage message displayed correctly"
else
    echo_fail "Usage message not displayed. Got: $output"
fi

# Test 2: Create test environment
echo_test "Creating test environment"
TEST_DIR=$(mktemp -d)
LOG_DIR="$TEST_DIR/test_logs"
mkdir -p "$LOG_DIR"

# Create test files with different dates
for i in {1..5}; do
    touch -d "$i days ago" "$LOG_DIR/file$i.log"
    echo "This is test file $i" > "$LOG_DIR/file$i.log"
done

if [ -d "$LOG_DIR" ] && [ $(ls "$LOG_DIR" | wc -l) -eq 5 ]; then
    echo_pass "Test environment created successfully"
else
    echo_fail "Failed to create test environment"
fi

# Test 3: Run script with exceeded threshold (should trigger archiving)
echo_test "Running script with exceeded threshold (should trigger archiving)"
# Create files to exceed threshold (N% of limit)
# Limit 10MB, N=50% = threshold 5MB, create 6MB to exceed
dd if=/dev/zero of="$LOG_DIR/large_file1.log" bs=1M count=3 2>/dev/null
dd if=/dev/zero of="$LOG_DIR/large_file2.log" bs=1M count=3 2>/dev/null

# Запускаем с флагом -y для автоматического подтверждения
output=$(bash manager.sh -y "$LOG_DIR" 10 50 2>&1)

# Check if archive created
if [ -d "$LOG_DIR/backup" ] && [ $(find "$LOG_DIR/backup" -name "*.tar.gz" | wc -l) -gt 0 ]; then
    echo_pass "Archive created successfully"
else
    echo_fail "Archive not created. Output: $output"
fi

# Test 4: Run script within threshold (should not trigger archiving)
echo_test "Running script within threshold (should not trigger archiving)"
CLEAN_DIR=$(mktemp -d)
mkdir -p "$CLEAN_DIR/logs"
touch "$CLEAN_DIR/logs/file1.log"
echo "small file" > "$CLEAN_DIR/logs/file1.log"

# Limit 100MB, N=20% = threshold 20MB, current size ~0MB - should not archive
output=$(bash manager.sh -y "$CLEAN_DIR/logs" 100 20 2>&1)

if echo "$output" | grep -q "Within threshold limits"; then
    echo_pass "Script correctly identified usage within threshold"
else
    echo_fail "Script did not correctly identify usage within threshold. Output: $output"
fi

rm -rf "$CLEAN_DIR"

# Test 5: Check exact threshold (should not archive)
echo_test "Testing exact threshold (should not archive)"
THRESH_DIR=$(mktemp -d)
mkdir -p "$THRESH_DIR/logs"
# Create size exactly at threshold: limit 10MB, N=50% = 5MB threshold
dd if=/dev/zero of="$THRESH_DIR/logs/file1.log" bs=1M count=5 2>/dev/null

output=$(bash manager.sh -y "$THRESH_DIR/logs" 10 50 2>&1)

if echo "$output" | grep -q "Within threshold limits"; then
    echo_pass "Script correctly handled exact threshold (no archiving needed)"
else
    echo_fail "Script failed at exact threshold. Output: $output"
fi

rm -rf "$THRESH_DIR"

# Test 6: Check non-existent directory handling
echo_test "Testing non-existent directory handling"
output=$(bash manager.sh -y "/invalid/path/that/doesnt/exist" 10 15 2>&1)

if echo "$output" | grep -q "Error: Directory"; then
    echo_pass "Script correctly handled non-existent directory"
else
    echo_fail "Script did not handle non-existent directory correctly. Output: $output"
fi

# Test 7: Check hard limit application (within threshold scenario)
echo_test "Testing hard limit application (within threshold)"
LIMIT_DIR=$(mktemp -d)
mkdir -p "$LIMIT_DIR/logs"
dd if=/dev/zero of="$LIMIT_DIR/logs/test_file.log" bs=1M count=2 2>/dev/null

# Apply 10MB limit, N=50% = 5MB threshold, current size 2MB - should apply hard limit
output=$(bash manager.sh -y "$LIMIT_DIR/logs" 10 50 2>&1)

if echo "$output" | grep -q "Folder now has hard limit"; then
    echo_pass "Hard limit applied successfully"
else
    echo_fail "Hard limit not applied. Output: $output"
fi

# Cleanup mounted directory
sudo umount "$LIMIT_DIR/logs" 2>/dev/null
sudo rm -f "/limited_logs.img" 2>/dev/null
sudo sed -i '\|/limited_logs.img|d' /etc/fstab 2>/dev/null
rm -rf "$LIMIT_DIR"

# Test 8: Test interactive mode flag
echo_test "Testing interactive mode flag"
# Тестируем флаг -i с автоматическими ответами
output=$(printf "n\n" | bash manager.sh -i 2>&1)

if echo "$output" | grep -q "Archiving Manager - Interactive Setup"; then
    echo_pass "Interactive mode started correctly"
else
    echo_fail "Interactive mode not working. Output: $output"
fi

# Test 9: Test archiving logic with multiple batches
echo_test "Testing archiving logic with multiple batches"
ARCHIVE_DIR=$(mktemp -d)
mkdir -p "$ARCHIVE_DIR/logs"

# Create many small files to test batch archiving
for i in {1..15}; do
    echo "file $i" > "$ARCHIVE_DIR/logs/file$i.log"
done

# Add some size to exceed threshold
dd if=/dev/zero of="$ARCHIVE_DIR/logs/large.log" bs=1M count=3 2>/dev/null

# Limit 5MB, N=50% = 2.5MB threshold, current size ~3MB - should archive
output=$(bash manager.sh -y "$ARCHIVE_DIR/logs" 5 50 2>&1)

if echo "$output" | grep -q "Archiving completed" && [ -d "$ARCHIVE_DIR/logs/backup" ]; then
    echo_pass "Batch archiving working correctly"
else
    echo_fail "Batch archiving failed. Output: $output"
fi

# Cleanup
sudo umount "$ARCHIVE_DIR/logs" 2>/dev/null
sudo rm -f "/limited_logs.img" 2>/dev/null
sudo sed -i '\|/limited_logs.img|d' /etc/fstab 2>/dev/null
rm -rf "$ARCHIVE_DIR"

# Cleanup main test directory
rm -rf "$TEST_DIR"

# Results
echo
echo "=== TEST RESULTS ==="
echo "Total tests: $TEST_COUNT"
echo "Passed: $PASSED_COUNT"
echo "Failed: $FAILED_COUNT"

if [ $FAILED_COUNT -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
