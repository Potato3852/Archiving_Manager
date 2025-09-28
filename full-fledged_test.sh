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

# Test 1: Check arguments
echo_test "Testing error message (wrong number of arguments)"
output=$(bash manager.sh 2>&1)
if echo "$output" | grep -q "Error: give 3 args"; then
    echo_pass "Error message displayed correctly"
else
    echo_fail "Error message not displayed. Got: $output"
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

# Test 3: Run script with exceeded limit (should trigger archiving)
echo_test "Running script with exceeded limit (should trigger archiving)"
# Create files to exceed limit by more than N%
dd if=/dev/zero of="$LOG_DIR/large_file1.log" bs=1M count=2 2>/dev/null
dd if=/dev/zero of="$LOG_DIR/large_file2.log" bs=1M count=2 2>/dev/null

# Limit 1MB, current size ~4MB = exceeds more than 15%
output=$(bash manager.sh "$LOG_DIR" 1 15 2>&1)

# Check if archive created and hard limit applied
if [ -d "$LOG_DIR/backup" ] && [ $(find "$LOG_DIR/backup" -name "*.tar.gz" | wc -l) -gt 0 ]; then
    echo_pass "Archive created successfully"
else
    echo_fail "Archive not created. Output: $output"
fi

# Test 4: Run script within limit + threshold (should not trigger archiving)
echo_test "Running script within limit + threshold (should not trigger archiving)"
CLEAN_DIR=$(mktemp -d)
mkdir -p "$CLEAN_DIR/logs"
touch "$CLEAN_DIR/logs/file1.log"
echo "small file" > "$CLEAN_DIR/logs/file1.log"

# Limit 100MB, current size ~0MB, N=15% - should not archive
output=$(bash manager.sh "$CLEAN_DIR/logs" 100 15 2>&1)

if echo "$output" | grep -q "Within threshold limits"; then
    echo_pass "Script correctly identified usage within limits"
else
    echo_fail "Script did not correctly identify usage within limits. Output: $output"
fi

rm -rf "$CLEAN_DIR"

# Test 5: Check exact threshold (should not archive)
echo_test "Testing exact threshold (should not archive)"
THRESH_DIR=$(mktemp -d)
mkdir -p "$THRESH_DIR/logs"
# Create size ~115MB with limit 100MB and N=15 (exact threshold)
dd if=/dev/zero of="$THRESH_DIR/logs/file1.log" bs=1M count=115 2>/dev/null

output=$(bash manager.sh "$THRESH_DIR/logs" 100 15 2>&1)

if echo "$output" | grep -q "Within threshold limits"; then
    echo_pass "Script correctly handled exact threshold"
else
    echo_fail "Script failed at exact threshold. Output: $output"
fi

rm -rf "$THRESH_DIR"

# Test 6: Check non-existent directory handling
echo_test "Testing non-existent directory handling"
output=$(bash manager.sh "/invalid/path/that/doesnt/exist" 10 15 2>&1)

if echo "$output" | grep -q "Error: Directory"; then
    echo_pass "Script correctly handled non-existent directory"
else
    echo_fail "Script did not handle non-existent directory correctly. Output: $output"
fi

# Test 7: Check hard limit application
echo_test "Testing hard limit application"
LIMIT_DIR=$(mktemp -d)
mkdir -p "$LIMIT_DIR/logs"
dd if=/dev/zero of="$LIMIT_DIR/logs/test_file.log" bs=1M count=50 2>/dev/null

# Apply 100MB limit
bash manager.sh "$LIMIT_DIR/logs" 100 10 2>&1 > /dev/null

# Try to write file larger than limit
dd if=/dev/zero of="$LIMIT_DIR/logs/large_file.log" bs=1M count=150 2>/dev/null
if [ $? -ne 0 ]; then
    echo_pass "Hard limit working correctly"
else
    echo_fail "Hard limit not working"
fi

rm -rf "$LIMIT_DIR"

# Cleanup
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
