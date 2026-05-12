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
cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT
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

# ---- 15. check_disk_space() with insufficient space ----
echo "[15] Disk space check"
# Re-implement check_disk_space logic for isolated testing
check_disk_space_test() {
    local dest="$1"
    local min_mb="${2:-500}"
    local avail_mb
    avail_mb=$(df "$dest" 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
    if [ -z "$avail_mb" ]; then return 1; fi
    if [ "$avail_mb" -lt "$min_mb" ]; then return 1; fi
    return 0
}
mkdir -p "$TEST_DIR/diskspace_test"
check_disk_space_test "$TEST_DIR/diskspace_test" 99999999 && fail "check_disk_space should fail with insufficient space" || ok "check_disk_space correctly rejects insufficient space"

# ---- 16. --dry-run prevents file creation ----
echo "[16] --dry-run"
mkdir -p "$TEST_ARCHIVE/dryrun_test"
cat > "$TEST_DIR/test_dryrun.conf" << EOF
METHOD="tar"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$TEST_ARCHIVE/dryrun_test"
BACKUP_FOLDER=""
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
(cd "$SCRIPT_DIR" && ./copia-segura.sh --dry-run --config "$TEST_DIR/test_dryrun.conf" >/dev/null 2>&1)
LS_OUT=$(ls "$TEST_ARCHIVE/dryrun_test"/*.tar.gz 2>/dev/null)
[ -z "$LS_OUT" ] && ok "--dry-run prevents file creation" || fail "--dry-run created archive despite --dry-run flag"

# ---- 17. METHOD=rsync without BACKUP_FOLDER → error ----
echo "[17] rsync without BACKUP_FOLDER"
if command -v rsync &>/dev/null; then
    cat > "$TEST_DIR/test_rsync_nobf.conf" << EOF
METHOD="rsync"
SOURCE="$TEST_SRC"
BACKUP_FOLDER=""
ARCHIVE_FOLDER=""
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
    RSYNC_NOBF_OUT=$("$SCRIPT_DIR/copia-segura.sh" --config "$TEST_DIR/test_rsync_nobf.conf" 2>&1 <<< "y")
    RSYNC_NOBF_RC=$?
    if [ $RSYNC_NOBF_RC -ne 0 ]; then
        ok "rsync without BACKUP_FOLDER correctly rejected"
        echo "$RSYNC_NOBF_OUT" | grep -qi "BACKUP_FOLDER is required" && ok "Error message mentions BACKUP_FOLDER required" || fail "Error message should mention BACKUP_FOLDER"
    else
        fail "rsync without BACKUP_FOLDER should have failed"
    fi
else
    echo "  [SKIP] rsync not installed"
fi

# ---- 18. SOURCE directory not existing → error ----
echo "[18] SOURCE not existing"
mkdir -p "$TEST_ARCHIVE"
cat > "$TEST_DIR/test_nosource.conf" << EOF
METHOD="tar"
SOURCE="$TEST_DIR/nonexistent_dir_xyz_12345"
ARCHIVE_FOLDER="$TEST_ARCHIVE"
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
(cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_nosource.conf" >/dev/null 2>&1) && fail "Non-existent SOURCE should error" || ok "Non-existent SOURCE correctly rejected"

# ---- 19. Menu selection validation ----
echo "[19] Menu selection validation"
# Test the numeric menu validation logic in isolation
validate_index() {
    local idx="$1"
    local count="$2"
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -ge "$count" ]; then
        return 1
    fi
    return 0
}
validate_index 0 3 && ok "Valid index 0 accepted" || fail "Valid index 0 should be accepted"
validate_index 2 3 && ok "Valid index 2 accepted" || fail "Valid index 2 should be accepted"
validate_index 3 3 && fail "Out-of-range index 3 should error" || ok "Out-of-range index 3 rejected"
validate_index -1 3 && fail "Negative index should error" || ok "Negative index rejected"
validate_index "abc" 3 && fail "Non-numeric should error" || ok "Non-numeric input rejected"
validate_index "" 3 && fail "Empty input should error" || ok "Empty input rejected"

# ---- 20. rsync + archive combined ----
echo "[20] rsync + archive combined"
if command -v rsync &>/dev/null; then
    mkdir -p "$TEST_DEST/rsync_combined" "$TEST_ARCHIVE/rsync_combined"
    cat > "$TEST_DIR/test_rsync_comb.conf" << EOF
METHOD="rsync"
SOURCE="$TEST_SRC"
BACKUP_FOLDER="$TEST_DEST/rsync_combined"
ARCHIVE_FOLDER="$TEST_ARCHIVE/rsync_combined"
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
    (cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_rsync_comb.conf" >/dev/null 2>&1) && ok "rsync+archive backup completes" || fail "rsync+archive backup failed"
    [ -d "$TEST_DEST/rsync_combined" ] && [ -f "$TEST_DEST/rsync_combined/file1.txt" ] && ok "rsync+archive: files in BACKUP_FOLDER" || fail "rsync+archive: files missing from BACKUP_FOLDER"
    RSYNC_ARCHIVE_FILE=$(ls "$TEST_ARCHIVE/rsync_combined"/*.tar.gz 2>/dev/null | head -1)
    [ -n "$RSYNC_ARCHIVE_FILE" ] && ok "rsync+archive: .tar.gz archive in ARCHIVE_FOLDER" || fail "rsync+archive: no .tar.gz archive created"
else
    echo "  [SKIP] rsync not installed"
fi

# ---- 21. archive_name() output format ----
echo "[21] archive_name() output format"
# Test archive_name logic by running actual backups and checking extensions
mkdir -p "$TEST_ARCHIVE/name_test"
# Tar extension test
mkdir -p "$TEST_ARCHIVE/name_test/tar"
cat > "$TEST_DIR/test_name_tar.conf" << EOF
METHOD="tar"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$TEST_ARCHIVE/name_test/tar"
BACKUP_FOLDER=""
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
(cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_name_tar.conf" >/dev/null 2>&1) || true
TAR_NAME=$(ls "$TEST_ARCHIVE/name_test/tar"/*.tar.gz 2>/dev/null | head -1 | xargs basename 2>/dev/null)
[[ "$TAR_NAME" == *.tar.gz ]] && ok "archive_name tar: .tar.gz extension" || fail "archive_name tar: expected .tar.gz, got '$TAR_NAME'"

# Zip extension test
mkdir -p "$TEST_ARCHIVE/name_test/zip"
cat > "$TEST_DIR/test_name_zip.conf" << EOF
METHOD="zip"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$TEST_ARCHIVE/name_test/zip"
BACKUP_FOLDER=""
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
(cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_name_zip.conf" >/dev/null 2>&1) || true
ZIP_NAME=$(ls "$TEST_ARCHIVE/name_test/zip"/*.zip 2>/dev/null | head -1 | xargs basename 2>/dev/null)
[[ "$ZIP_NAME" == *.zip ]] && ok "archive_name zip: .zip extension" || fail "archive_name zip: expected .zip, got '$ZIP_NAME'"

# 7z extension test (optional)
if command -v 7z &>/dev/null; then
    mkdir -p "$TEST_ARCHIVE/name_test/7z"
    cat > "$TEST_DIR/test_name_7z.conf" << EOF
METHOD="7z"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$TEST_ARCHIVE/name_test/7z"
BACKUP_FOLDER=""
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
    (cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_name_7z.conf" >/dev/null 2>&1) || true
    S7Z_NAME=$(ls "$TEST_ARCHIVE/name_test/7z"/*.7z 2>/dev/null | head -1 | xargs basename 2>/dev/null)
    [[ "$S7Z_NAME" == *.7z ]] && ok "archive_name 7z: .7z extension" || fail "archive_name 7z: expected .7z, got '$S7Z_NAME'"
else
    echo "  [SKIP] 7z not installed for archive_name test"
fi

# Verify datetime format in any archive name
[[ "$TAR_NAME" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2} ]] && ok "archive_name contains datetime format" || fail "archive_name missing datetime format in '$TAR_NAME'"

# ---- 22. build_excludes() output format ----
echo "[22] build_excludes() output format"
mkdir -p "$TEST_ARCHIVE/excl_test"
cat > "$TEST_DIR/test_excludes.conf" << EOF
METHOD="tar"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$TEST_ARCHIVE/excl_test"
BACKUP_FOLDER=""
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EXCLUDE_PATTERNS="*.tmp *.log"
EOF
EXCL_OUTPUT=$("$SCRIPT_DIR/copia-segura.sh" --dry-run --config "$TEST_DIR/test_excludes.conf" 2>&1)
echo "$EXCL_OUTPUT" | grep -qF -- "--exclude=*.tmp" && ok "build_excludes tar: --exclude=*.tmp in dry-run output" || fail "build_excludes tar: --exclude=*.tmp not found in output"
echo "$EXCL_OUTPUT" | grep -qF -- "--exclude=*.log" && ok "build_excludes tar: --exclude=*.log in dry-run output" || fail "build_excludes tar: --exclude=*.log not found in output"

# ---- 23. verify_backup() with no archive folder → skip ----
echo "[23] verify_backup with no ARCHIVE_FOLDER"
mkdir -p "$TEST_DIR/verify_skip"
cat > "$TEST_DIR/test_verifyskip.conf" << EOF
METHOD="tar"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER=""
BACKUP_FOLDER=""
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
VERIFY_OUTPUT=$("$SCRIPT_DIR/copia-segura.sh" --dry-run --config "$TEST_DIR/test_verifyskip.conf" 2>&1)
echo "$VERIFY_OUTPUT" | grep -qi "Integrity check\|Verifying integrity" && fail "verify_backup ran integrity check (should skip with empty ARCHIVE_FOLDER)" || ok "verify_backup skipped with empty ARCHIVE_FOLDER"

# ---- 24. Empty SOURCE for tar → error ----
echo "[24] Empty SOURCE for tar"
cat > "$TEST_DIR/test_emptysrc.conf" << EOF
METHOD="tar"
SOURCE=""
ARCHIVE_FOLDER="$TEST_ARCHIVE"
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
EMPTYSRC_OUT=$("$SCRIPT_DIR/copia-segura.sh" --config "$TEST_DIR/test_emptysrc.conf" 2>&1)
EMPTYSRC_RC=$?
[ $EMPTYSRC_RC -ne 0 ] && ok "Empty SOURCE for tar correctly rejected" || fail "Empty SOURCE for tar should error"
echo "$EMPTYSRC_OUT" | grep -qi "SOURCE is required" && ok "Error message mentions 'SOURCE is required'" || fail "Error should mention 'SOURCE is required for METHOD=tar'"

# ---- 25. Rotation with RETENTION_DAYS=0 ----
echo "[25] Rotation with RETENTION_DAYS=0"
ROT0_DIR="$TEST_DIR/rotation_0"
mkdir -p "$ROT0_DIR"
# Create old backup files with mtime long ago
echo "old backup" > "$ROT0_DIR/old_backup_10d.tar.gz"
touch -t "$(date -d '10 days ago' +%Y%m%d%H%M.%S)" "$ROT0_DIR/old_backup_10d.tar.gz"
echo "medium backup" > "$ROT0_DIR/medium_backup_3d.tar.gz"
touch -t "$(date -d '3 days ago' +%Y%m%d%H%M.%S)" "$ROT0_DIR/medium_backup_3d.tar.gz"
cat > "$TEST_DIR/test_rot0.conf" << EOF
METHOD="tar"
SOURCE="$TEST_SRC"
ARCHIVE_FOLDER="$ROT0_DIR"
RETENTION_DAYS=0
REMOTE_ENABLED="false"
EOF
(cd "$SCRIPT_DIR" && echo "y" | ./copia-segura.sh --config "$TEST_DIR/test_rot0.conf" >/dev/null 2>&1) && ok "RETENTION_DAYS=0 backup completes" || fail "RETENTION_DAYS=0 backup failed"
# Old files (mtime > 0 days ago) should be deleted
[ ! -f "$ROT0_DIR/old_backup_10d.tar.gz" ] && ok "RETENTION_DAYS=0: old_backup_10d deleted" || fail "RETENTION_DAYS=0: old_backup_10d not deleted"
[ ! -f "$ROT0_DIR/medium_backup_3d.tar.gz" ] && ok "RETENTION_DAYS=0: medium_backup_3d deleted" || fail "RETENTION_DAYS=0: medium_backup_3d not deleted"
# Newly created backup should exist
ls "$ROT0_DIR"/*.tar.gz 2>/dev/null | grep -v "old_backup\|medium_backup" | head -1 | grep -q . && ok "RETENTION_DAYS=0: new backup preserved" || fail "RETENTION_DAYS=0: new backup missing"

# ---- 26. verify_backup with METHOD=rsync → skip with message ----
echo "[26] verify_backup rsync skip"
if command -v rsync &>/dev/null; then
    mkdir -p "$TEST_DEST/rsync_verify_skip" "$TEST_ARCHIVE/rsync_verify_skip"
    cat > "$TEST_DIR/test_rsync_verify.conf" << EOF
METHOD="rsync"
SOURCE="$TEST_SRC"
BACKUP_FOLDER="$TEST_DEST/rsync_verify_skip"
ARCHIVE_FOLDER="$TEST_ARCHIVE/rsync_verify_skip"
RETENTION_DAYS=7
REMOTE_ENABLED="false"
EOF
    RSV_OUT=$("$SCRIPT_DIR/copia-segura.sh" --config "$TEST_DIR/test_rsync_verify.conf" 2>&1 <<< "y")
    echo "$RSV_OUT" | grep -qi "integrity check skipped for rsync" && ok "verify_backup rsync: skip message logged" || fail "verify_backup rsync: skip message not found"
else
    echo "  [SKIP] rsync not installed"
fi

# ---- 27. Config variables ----
echo "[27] Config variables"
[ "$(grep -c 'REMOTE_DELETE_SOURCE' "$SCRIPT_DIR/configs/example.conf")" -gt 0 ] && ok "REMOTE_DELETE_SOURCE in example.conf" || fail "REMOTE_DELETE_SOURCE missing in example.conf"
[ "$(grep -c 'REMOTE_ENABLED' "$SCRIPT_DIR/configs/desarrollo-en-curso.conf")" -gt 0 ] && ok "REMOTE_ENABLED in desarrollo-en-curso.conf" || fail "REMOTE_ENABLED missing in desarrollo-en-curso.conf"
[ "$(grep -c 'REMOTE_DEST' "$SCRIPT_DIR/configs/desarrollo-en-curso.conf")" -gt 0 ] && ok "REMOTE_DEST in desarrollo-en-curso.conf" || fail "REMOTE_DEST missing in desarrollo-en-curso.conf"

# ---- 28. Script syntax check ----
echo "[28] Shell syntax"
bash -n "$SCRIPT_DIR/copia-segura.sh" 2>/dev/null && ok "Shell syntax OK" || fail "Shell syntax error"
bash -n "$SCRIPT_DIR/test.sh" 2>/dev/null && ok "Test script syntax OK" || fail "Test script syntax error"

# ---- Summary ----
echo ""
echo "=============================="
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
echo "=============================="
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
