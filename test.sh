#!/bin/bash
# =============================================================
# test.sh — Test suite for copia-segura
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
TOTAL=0

ok()   { ((TOTAL++)); ((PASS++)); echo "  [PASS] $1"; }
fail() { ((TOTAL++)); ((FAIL++)); echo "  [FAIL] $1"; }

# ---- Test environment ----
TEST_DIR=$(mktemp -d)
TEST_SRC="$TEST_DIR/source"
TEST_DEST="$TEST_DIR/dest"
TEST_ARCHIVE="$TEST_DIR/archive"
mkdir -p "$TEST_SRC/subdir"
echo "hello world" > "$TEST_SRC/file1.txt"
echo "test data" > "$TEST_SRC/subdir/file2.txt"
echo "temporary.tmp" > "$TEST_SRC/temp.tmp"

echo ""
echo "=============================="
echo "  copia-segura — Test Suite"
echo "=============================="
echo ""

# ---- 1. Script exists and is executable ----
echo "[1] Script integrity"
[ -f "$SCRIPT_DIR/copia-segura.sh" ] && ok "copia-segura.sh exists" || fail "copia-segura.sh not found"
[ -x "$SCRIPT_DIR/copia-segura.sh" ] && ok "copia-segura.sh is executable" || fail "copia-segura.sh not executable"

# ---- 2. Config files exist ----
echo "[2] Configuration files"
[ -f "$SCRIPT_DIR/configs/example.conf" ] && ok "example.conf exists" || fail "example.conf not found"
[ -f "$SCRIPT_DIR/configs/desarrollo-en-curso.conf" ] && ok "desarrollo-en-curso.conf exists" || fail "desarrollo-en-curso.conf not found"

# ---- 3. Required commands ----
echo "[3] Required commands"
for cmd in tar zip find date; do
    command -v "$cmd" &>/dev/null && ok "$cmd found" || fail "$cmd not found"
done

# Check optional commands
command -v 7z &>/dev/null && ok "7z found (optional)" || echo "  [INFO] 7z not installed (optional, skipping 7z tests)"
command -v rsync &>/dev/null && ok "rsync found (optional)" || echo "  [INFO] rsync not installed (optional, skipping rsync tests)"
command -v rclone &>/dev/null && ok "rclone found (optional)" || echo "  [INFO] rclone not installed (optional, skipping upload tests)"

# ---- 4. METHOD=tar ----
echo "[4] METHOD=tar"
mkdir -p "$TEST_ARCHIVE/tar"
cat > "$TEST_DIR/test_tar.conf" << EOF
METHOD="tar"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$TEST_ARCHIVE/tar"
BACKUP_FOLDER=""
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EXCLUDE_PATTERNS="*.tmp"
EOF
(cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_tar.conf" >/dev/null 2>&1) && ok "tar backup completes" || fail "tar backup failed"

TAR_FILE=$(ls "$TEST_ARCHIVE/tar"/*.tar.gz 2>/dev/null | head -1)
[ -n "$TAR_FILE" ] && tar -tzf "$TAR_FILE" &>/dev/null && ok "tar archive is valid" || fail "tar archive invalid or missing"

# ---- 5. METHOD=zip ----
echo "[5] METHOD=zip"
mkdir -p "$TEST_ARCHIVE/zip"
cat > "$TEST_DIR/test_zip.conf" << EOF
METHOD="zip"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$TEST_ARCHIVE/zip"
BACKUP_FOLDER=""
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EXCLUDE_PATTERNS="*.tmp"
EOF
(cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_zip.conf" >/dev/null 2>&1) && ok "zip backup completes" || fail "zip backup failed"

ZIP_FILE=$(ls "$TEST_ARCHIVE/zip"/*.zip 2>/dev/null | head -1)
if [ -n "$ZIP_FILE" ]; then
    unzip -t "$ZIP_FILE" >/dev/null 2>&1 && ok "zip archive is valid" || fail "zip archive invalid"
    unzip -l "$ZIP_FILE" 2>/dev/null | grep -q "temp.tmp" && fail "zip did not exclude *.tmp" || ok "zip excluded *.tmp"
else
    fail "No zip file created"
fi

# ---- 6. METHOD=7z (if available) ----
echo "[6] METHOD=7z"
if command -v 7z &>/dev/null; then
    mkdir -p "$TEST_ARCHIVE/7z"
    cat > "$TEST_DIR/test_7z.conf" << EOF
METHOD="7z"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$TEST_ARCHIVE/7z"
BACKUP_FOLDER=""
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EXCLUDE_PATTERNS="*.tmp"
EOF
    (cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_7z.conf" >/dev/null 2>&1) && ok "7z backup completes" || fail "7z backup failed"
    SEVEN_FILE=$(ls "$TEST_ARCHIVE/7z"/*.7z 2>/dev/null | head -1)
    [ -n "$SEVEN_FILE" ] && 7z t "$SEVEN_FILE" >/dev/null 2>&1 && ok "7z archive is valid" || fail "7z archive invalid"
else
    echo "  [SKIP] 7z not installed"
fi

# ---- 7. METHOD=rsync (if available) ----
echo "[7] METHOD=rsync"
if command -v rsync &>/dev/null; then
    mkdir -p "$TEST_DEST/rsync" "$TEST_ARCHIVE/rsync"
    cat > "$TEST_DIR/test_rsync.conf" << EOF
METHOD="rsync"
SOURCE="$TEST_SRC"
BACKUP_FOLDER="$TEST_DEST/rsync"
ARCHIVE_FOLDER="$TEST_ARCHIVE/rsync"
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EXCLUDE_PATTERNS="*.tmp"
EOF
    (cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_rsync.conf" >/dev/null 2>&1) && ok "rsync backup completes" || fail "rsync backup failed"
    [ -d "$TEST_DEST/rsync" ] && [ -f "$TEST_DEST/rsync/file1.txt" ] && ok "rsync files present" || fail "rsync files missing"
else
    echo "  [SKIP] rsync not installed"
fi

# ---- 7b. METHOD=rsync incremental (second run) ----
echo "[7b] rsync incremental"
if command -v rsync &>/dev/null; then
    # Add a new file after first rsync run
    echo "new content" > "$TEST_SRC/newfile.txt"
    (cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_rsync.conf" >/dev/null 2>&1) && ok "rsync second run completes" || fail "rsync second run failed"
    [ -f "$TEST_DEST/rsync/newfile.txt" ] && ok "rsync incremental: new file synced" || fail "rsync incremental: new file missing"
else
    echo "  [SKIP] rsync not installed"
fi

# ---- 8. Exclusion patterns ----
echo "[8] Exclusion patterns"
[ "$(grep -c 'EXCLUDE_PATTERNS' "$SCRIPT_DIR/configs/example.conf")" -gt 0 ] && ok "EXCLUDE_PATTERNS in example.conf" || fail "EXCLUDE_PATTERNS missing"

# ---- 9. Remote config variables ----
echo "[9] Remote upload config"
[ "$(grep -c 'REMOTE_ENABLED' "$SCRIPT_DIR/configs/example.conf")" -gt 0 ] && ok "REMOTE_ENABLED in example.conf" || fail "REMOTE_ENABLED missing"
[ "$(grep -c 'REMOTE_DEST' "$SCRIPT_DIR/configs/example.conf")" -gt 0 ] && ok "REMOTE_DEST in example.conf" || fail "REMOTE_DEST missing"

# ---- 10. CLI options ----
echo "[10] CLI options"
"$SCRIPT_DIR/copia-segura.sh" --help >/dev/null 2>&1 && ok "--help works" || fail "--help failed"
"$SCRIPT_DIR/copia-segura.sh" --list >/dev/null 2>&1 && ok "--list works" || fail "--list failed"
# Test --dry-run + --config with a valid config that exists
cat > "$SCRIPT_DIR/configs/_test_cli.conf" << EOF
METHOD="tar"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$TEST_ARCHIVE/cli_test"
BACKUP_FOLDER=""
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
mkdir -p "$TEST_ARCHIVE/cli_test"
(cd "$SCRIPT_DIR" && ./copia-segura.sh --dry-run --config _test_cli.conf >/dev/null 2>&1) && ok "--dry-run + --config works" || fail "--dry-run + --config failed"
rm -f "$SCRIPT_DIR/configs/_test_cli.conf"

# ---- 11. Invalid method ----
echo "[11] Error handling"
cat > "$TEST_DIR/test_invalid.conf" << EOF
METHOD="invalid_format"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$TEST_ARCHIVE"
EOF
"$SCRIPT_DIR/copia-segura.sh" --config "$TEST_DIR/test_invalid.conf" >/dev/null 2>&1 && fail "Invalid method should error" || ok "Invalid method properly rejected"

# ---- 12. Backup rotation test ----
echo "[12] Backup rotation"
ROT_DIR="$TEST_DIR/rotation"
mkdir -p "$ROT_DIR"
# Create an "old" backup file (mtime = 10 days ago, exceeds default RETENTION_DAYS=7)
echo "old backup content" > "$ROT_DIR/old_backup.tar.gz"
touch -t "$(date -d '10 days ago' +%Y%m%d%H%M.%S)" "$ROT_DIR/old_backup.tar.gz"
cat > "$TEST_DIR/test_rot.conf" << EOF
METHOD="tar"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$ROT_DIR"
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
(cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_rot.conf" >/dev/null 2>&1) && ok "rotation backup completes" || fail "rotation backup failed"
# Old backup should be deleted after rotation
[ ! -f "$ROT_DIR/old_backup.tar.gz" ] && ok "rotation deleted old backup (mtime +7 days)" || fail "rotation did NOT delete old backup"
# New backup should exist
ls "$ROT_DIR"/*.tar.gz 2>/dev/null | grep -v "old_backup" | head -1 | grep -q . && ok "rotation: new backup preserved" || fail "rotation: new backup missing"

# ---- 13. Corrupt archive detection ----
echo "[13] Corrupt archive detection"
COR_DIR="$TEST_DIR/corrupt"
mkdir -p "$COR_DIR"
# Create a valid tar first, then corrupt it
mkdir -p "$TEST_DIR/corrupt_src" && echo "valid data" > "$TEST_DIR/corrupt_src/file.txt"
tar -czf "$COR_DIR/good.tar.gz" -C "$TEST_DIR/corrupt_src" . 2>/dev/null
# Corrupt by appending garbage
echo "CORRUPTION_DATA" >> "$COR_DIR/good.tar.gz"
# Test that tar -tzf fails (same mechanism as verify_backup uses)
tar -tzf "$COR_DIR/good.tar.gz" &>/dev/null && fail "corrupt archive incorrectly passed verification" || ok "corrupt archive correctly rejected by tar -tzf"

# ---- 14. Config variables ----
echo "[14] Config variables"
[ "$(grep -c 'REMOTE_DELETE_SOURCE' "$SCRIPT_DIR/configs/example.conf")" -gt 0 ] && ok "REMOTE_DELETE_SOURCE in example.conf" || fail "REMOTE_DELETE_SOURCE missing in example.conf"
[ "$(grep -c 'REMOTE_ENABLED' "$SCRIPT_DIR/configs/desarrollo-en-curso.conf")" -gt 0 ] && ok "REMOTE_ENABLED in desarrollo-en-curso.conf" || fail "REMOTE_ENABLED missing in desarrollo-en-curso.conf"
[ "$(grep -c 'REMOTE_DEST' "$SCRIPT_DIR/configs/desarrollo-en-curso.conf")" -gt 0 ] && ok "REMOTE_DEST in desarrollo-en-curso.conf" || fail "REMOTE_DEST missing in desarrollo-en-curso.conf"

# ---- 15. Script syntax check ----
echo "[15] Shell syntax"
bash -n "$SCRIPT_DIR/copia-segura.sh" 2>/dev/null && ok "Shell syntax OK" || fail "Shell syntax error"
bash -n "$SCRIPT_DIR/test.sh" 2>/dev/null && ok "Test script syntax OK" || fail "Test script syntax error"

# ---- Summary ----
echo ""
echo "=============================="
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
echo "=============================="
echo ""

# Cleanup test directory
rm -rf "$TEST_DIR"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
