#!/bin/bash
# =============================================================
# copia-segura.sh — Safe Backup Tool
# Supports: tar, zip, 7z, rsync. Remote upload via rclone.
# License: MIT
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/configs"
LOG_DIR="$SCRIPT_DIR/logs"

# ---- Color output ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---- Defaults ----
DRY_RUN=false
SELECTED_CONFIG=""

# ---- Helpers ----
timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

log() {
    local level="$1"
    local msg="$2"
    echo "[$(timestamp)] [$level] $msg" | tee -a "$LOG_FILE"
}

log_ok()    { log "OK"    "$1"; echo -e "  ${GREEN}[OK]${NC} $1"; }
log_info()  { log "INFO"  "$1"; echo -e "  ${CYAN}[INFO]${NC} $1"; }
log_warn()  { log "WARN"  "$1"; echo -e "  ${YELLOW}[WARN]${NC} $1"; }
log_error() { log "ERROR" "$1"; echo -e "  ${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<EOF
Usage: ./copia-segura.sh [options]

Options:
  --config <name>    Run with a specific config file (no menu)
  --dry-run          Simulate without creating backups
  --list             List available configs and exit
  --help             Show this help
EOF
    exit 0
}

# ---- Parse CLI args ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) SELECTED_CONFIG="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --list) ls "$CONFIG_DIR"/*.conf 2>/dev/null | while read f; do echo "  $(basename "$f")"; done; exit 0 ;;
        --help|-h) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# ---- Find config ----
CONF_FILES=("$CONFIG_DIR"/*.conf)

if [ ! -d "$CONFIG_DIR" ]; then
    echo "Error: Config directory '$CONFIG_DIR' does not exist!"
    exit 1
fi

if [ ${#CONF_FILES[@]} -eq 0 ]; then
    echo "Error: No .conf files found in '$CONFIG_DIR'."
    exit 1
fi

if [ -n "$SELECTED_CONFIG" ]; then
    if [ -f "$SELECTED_CONFIG" ]; then
        CONFIG_FILE="$SELECTED_CONFIG"
    elif [ -f "$CONFIG_DIR/$SELECTED_CONFIG" ]; then
        CONFIG_FILE="$CONFIG_DIR/$SELECTED_CONFIG"
    else
        echo "Error: Config '$SELECTED_CONFIG' not found (tried: $SELECTED_CONFIG and $CONFIG_DIR/$SELECTED_CONFIG)"
        exit 1
    fi
    echo "Using configuration: $(basename "$CONFIG_FILE")"
elif [ ${#CONF_FILES[@]} -eq 1 ]; then
    CONFIG_FILE="${CONF_FILES[0]}"
    echo "Only one configuration found. Using: $(basename "$CONFIG_FILE")"
else
    echo ""
    echo "Available backup configurations:"
    for i in "${!CONF_FILES[@]}"; do
        echo "  [$i] $(basename "${CONF_FILES[$i]}")"
    done
    echo ""
    read -p "Select a configuration to run (number): " index
    if ! [[ "$index" =~ ^[0-9]+$ ]] || [ "$index" -ge "${#CONF_FILES[@]}" ]; then
        echo "Error: Invalid selection."
        exit 1
    fi
    CONFIG_FILE="${CONF_FILES[$index]}"
    echo "Using configuration: $(basename "$CONFIG_FILE")"
fi

# ---- Load config ----
source "$CONFIG_FILE"

# ---- Apply defaults ----
METHOD="${METHOD:-tar}"
SOURCE="${SOURCE:-}"
BACKUP_FOLDER="${BACKUP_FOLDER:-}"
ARCHIVE_FOLDER="${ARCHIVE_FOLDER:-}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
REMOTE_ENABLED="${REMOTE_ENABLED:-false}"
REMOTE_DEST="${REMOTE_DEST:-}"
REMOTE_OPTS="${REMOTE_OPTS:-}"
REMOTE_DELETE_SOURCE="${REMOTE_DELETE_SOURCE:-false}"
EXCLUDE_PATTERNS="${EXCLUDE_PATTERNS:-}"

# ---- Setup log ----
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/backup_$(date +%Y-%m-%d).log"

# ---- Validate METHOD ----
VALID_METHODS=("tar" "zip" "7z" "rsync")
VALID=false
for m in "${VALID_METHODS[@]}"; do
    [ "$METHOD" = "$m" ] && VALID=true
done
if [ "$VALID" = false ]; then
    echo "Error: Invalid METHOD '$METHOD'. Must be: tar, zip, 7z, or rsync."
    exit 1
fi

# ---- Validate paths ----
if [ -z "$SOURCE" ] && [ "$METHOD" != "rsync" ]; then
    echo "Error: SOURCE is required for METHOD=$METHOD."
    exit 1
fi

if [ -n "$SOURCE" ] && [ ! -d "$SOURCE" ]; then
    echo "Error: SOURCE directory '$SOURCE' does not exist."
    exit 1
fi

# ---- Check required commands ----
check_deps() {
    local missing=()
    case "$METHOD" in
        tar) command -v tar >/dev/null 2>&1 || missing+=("tar") ;;
        zip) command -v zip >/dev/null 2>&1 || missing+=("zip") ;;
        7z)  command -v 7z  >/dev/null 2>&1 || missing+=("7z (p7zip-full)") ;;
        rsync) command -v rsync >/dev/null 2>&1 || missing+=("rsync") ;;
    esac
    if [ "$REMOTE_ENABLED" = "true" ]; then
        command -v rclone >/dev/null 2>&1 || missing+=("rclone")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing required commands: ${missing[*]}"
        exit 1
    fi
}

# ---- Disk space check ----
check_disk_space() {
    local dest="$1"
    local min_mb="${2:-500}"
    local avail_mb
    avail_mb=$(df "$dest" 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
    if [ -z "$avail_mb" ]; then
        log_error "Cannot read disk space for $dest"
        return 1
    fi
    log_info "Available disk space: ${avail_mb}MB (minimum required: ${min_mb}MB)"
    if [ "$avail_mb" -lt "$min_mb" ]; then
        log_error "Not enough disk space! Only ${avail_mb}MB free."
        return 1
    fi
    return 0
}

# ---- Generate archive name ----
archive_name() {
    local src_name
    src_name=$(basename "$SOURCE")
    local date_str
    date_str=$(date +"%Y-%m-%d_%H-%M-%S")
    case "$METHOD" in
        tar) echo "${src_name}_${date_str}.tar.gz" ;;
        zip) echo "${src_name}_${date_str}.zip" ;;
        7z)  echo "${src_name}_${date_str}.7z" ;;
        *)   echo "${src_name}_${date_str}.tar.gz" ;;
    esac
}

# ---- Build exclude flags ----
build_excludes() {
    local tool="$1"
    local result=""
    if [ -z "$EXCLUDE_PATTERNS" ]; then
        echo "$result"
        return
    fi
    for pattern in $EXCLUDE_PATTERNS; do
        case "$tool" in
            tar)   result="$result --exclude=$pattern" ;;
            zip)   result="$result -x $pattern" ;;
            7z)    result="$result -xr!$pattern" ;;
            rsync) result="$result --exclude=$pattern" ;;
        esac
    done
    echo "$result"
}

# ---- Phase 1 & 2: Backup execution ----
run_backup() {
    local dest_dir
    local excl

    case "$METHOD" in
        tar)
            dest_dir="$ARCHIVE_FOLDER"
            mkdir -p "$dest_dir"
            local fname
            fname=$(archive_name)
            excl=$(build_excludes "tar")
            log_info "Compressing with tar: $SOURCE -> $dest_dir/$fname"
            if [ "$DRY_RUN" = false ]; then
                # shellcheck disable=SC2086
                tar -czf "$dest_dir/$fname" $excl -C "$(dirname "$SOURCE")" "$(basename "$SOURCE")" 2>>"$LOG_FILE"
                if [ $? -eq 0 ]; then
                    local size
                    size=$(du -sh "$dest_dir/$fname" | cut -f1)
                    log_ok "Backup created: $fname ($size)"
                else
                    log_error "tar compression failed!"
                    return 1
                fi
            else
                log_info "[DRY-RUN] Would run: tar -czf $dest_dir/$fname $excl $SOURCE"
            fi
            ;;

        zip)
            dest_dir="$ARCHIVE_FOLDER"
            mkdir -p "$dest_dir"
            local fname
            fname=$(archive_name)
            excl=$(build_excludes "zip")
            log_info "Compressing with zip: $SOURCE -> $dest_dir/$fname"
            if [ "$DRY_RUN" = false ]; then
                # shellcheck disable=SC2086
                (cd "$(dirname "$SOURCE")" && zip -r "$dest_dir/$fname" "$(basename "$SOURCE")" $excl) 2>>"$LOG_FILE"
                if [ $? -eq 0 ]; then
                    local size
                    size=$(du -sh "$dest_dir/$fname" | cut -f1)
                    log_ok "Backup created: $fname ($size)"
                else
                    log_error "zip compression failed!"
                    return 1
                fi
            else
                log_info "[DRY-RUN] Would run: zip -r $dest_dir/$fname $excl $SOURCE"
            fi
            ;;

        7z)
            dest_dir="$ARCHIVE_FOLDER"
            mkdir -p "$dest_dir"
            local fname
            fname=$(archive_name)
            excl=$(build_excludes "7z")
            log_info "Compressing with 7z: $SOURCE -> $dest_dir/$fname"
            if [ "$DRY_RUN" = false ]; then
                # shellcheck disable=SC2086
                7z a -t7z "$dest_dir/$fname" "$SOURCE" $excl >>"$LOG_FILE" 2>&1
                if [ $? -eq 0 ]; then
                    local size
                    size=$(du -sh "$dest_dir/$fname" | cut -f1)
                    log_ok "Backup created: $fname ($size)"
                else
                    log_error "7z compression failed!"
                    return 1
                fi
            else
                log_info "[DRY-RUN] Would run: 7z a -t7z $dest_dir/$fname $SOURCE $excl"
            fi
            ;;

        rsync)
            if [ -z "$BACKUP_FOLDER" ]; then
                log_error "BACKUP_FOLDER is required for METHOD=rsync"
                return 1
            fi
            dest_dir="$BACKUP_FOLDER"
            mkdir -p "$dest_dir"
            excl=$(build_excludes "rsync")
            log_info "Running rsync incremental: $SOURCE/ -> $dest_dir/"
            if [ "$DRY_RUN" = false ]; then
                # shellcheck disable=SC2086
                rsync -av --delete $excl "$SOURCE/" "$dest_dir/" >>"$LOG_FILE" 2>&1
                local rsync_exit=$?
                if [ $rsync_exit -eq 0 ] || [ $rsync_exit -eq 24 ]; then
                    log_ok "rsync completed successfully"
                    # If ARCHIVE_FOLDER is also set, compress the backup folder
                    if [ -n "$ARCHIVE_FOLDER" ]; then
                        mkdir -p "$ARCHIVE_FOLDER"
                        local src_name
                        src_name=$(basename "$SOURCE")
                        local date_str
                        date_str=$(date +"%Y-%m-%d_%H-%M-%S")
                        local fname="${src_name}_${date_str}.tar.gz"
                        log_info "Compressing rsync target into archive: $fname"
                        tar -czf "$ARCHIVE_FOLDER/$fname" -C "$dest_dir" . 2>>"$LOG_FILE"
                        if [ $? -eq 0 ]; then
                            local size
                            size=$(du -sh "$ARCHIVE_FOLDER/$fname" | cut -f1)
                            log_ok "Archive created: $fname ($size)"
                        else
                            log_error "Archive compression failed!"
                        fi
                    fi
                else
                    log_error "rsync failed with code $rsync_exit"
                    return 1
                fi
            else
                log_info "[DRY-RUN] Would run: rsync -av --delete $excl $SOURCE/ $dest_dir/"
            fi
            ;;
    esac
    return 0
}

# ---- Phase 4: Integrity verification ----
verify_backup() {
    local latest
    if [ "$METHOD" = "rsync" ]; then
        log_info "rsync does not produce a single archive file; integrity check skipped for rsync step."
        return 0
    fi
    if [ -z "$ARCHIVE_FOLDER" ]; then
        return 0
    fi
    latest=$(ls -t "$ARCHIVE_FOLDER"/*."${METHOD#rsync}"* 2>/dev/null | head -1)
    [ -z "$latest" ] && latest=$(ls -t "$ARCHIVE_FOLDER"/*.tar.gz "$ARCHIVE_FOLDER"/*.zip "$ARCHIVE_FOLDER"/*.7z 2>/dev/null | head -1)
    if [ -z "$latest" ]; then
        log_warn "No backup file found to verify."
        return 0
    fi
    log_info "Verifying integrity of: $(basename "$latest")"
    local ok=true
    case "$METHOD" in
        tar)
            tar -tzf "$latest" &>/dev/null || ok=false
            ;;
        zip)
            unzip -t "$latest" >/dev/null 2>&1 || ok=false
            ;;
        7z)
            7z t "$latest" >/dev/null 2>&1 || ok=false
            ;;
    esac
    if [ "$ok" = true ]; then
        log_ok "Integrity check PASSED: $(basename "$latest")"
    else
        log_error "Integrity check FAILED: $(basename "$latest") may be corrupt!"
    fi
}

# ---- Phase 4: Rotation ----
rotate_backups() {
    local target_dir
    local pattern

    if [ "$METHOD" = "rsync" ]; then
        target_dir="$BACKUP_FOLDER"
        if [ -z "$target_dir" ]; then
            log_info "No BACKUP_FOLDER set for rsync rotation."
            return
        fi
        pattern="*"
    else
        target_dir="$ARCHIVE_FOLDER"
        if [ -z "$target_dir" ]; then
            return
        fi
        case "$METHOD" in
            tar) pattern="*.tar.gz" ;;
            zip) pattern="*.zip" ;;
            7z)  pattern="*.7z" ;;
            *)   pattern="*" ;;
        esac
    fi

    log_info "Rotating backups older than ${RETENTION_DAYS} days in $target_dir..."
    local deleted=0
    while IFS= read -r -d '' old_file; do
        rm -f "$old_file"
        log_info "Deleted old backup: $(basename "$old_file")"
        ((deleted++))
    done < <(find "$target_dir" -name "$pattern" -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)

    if [ "$deleted" -eq 0 ]; then
        log_info "No old backups to rotate."
    else
        log_info "Rotation complete. Removed $deleted old backup(s)."
    fi
}

# ---- Phase 3: Remote upload via rclone ----
remote_upload() {
    if [ "$REMOTE_ENABLED" != "true" ] || [ -z "$REMOTE_DEST" ]; then
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would run: rclone copy <local> $REMOTE_DEST"
        return 0
    fi
    local src_path=""
    if [ "$METHOD" = "rsync" ] && [ -n "$BACKUP_FOLDER" ]; then
        src_path="$BACKUP_FOLDER"
    elif [ -n "$ARCHIVE_FOLDER" ]; then
        src_path="$ARCHIVE_FOLDER"
    else
        log_warn "No source path for remote upload."
        return 0
    fi
    log_info "Uploading to remote: $src_path -> $REMOTE_DEST"
    # shellcheck disable=SC2086
    rclone copy "$src_path" "$REMOTE_DEST" $REMOTE_OPTS >>"$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log_ok "Remote upload completed successfully"
        if [ "$REMOTE_DELETE_SOURCE" = "true" ]; then
            log_info "REMOTE_DELETE_SOURCE is enabled. Removing local backup files..."
            rm -rf "$src_path"/*
            log_ok "Local backup files removed from $src_path"
        fi
    else
        log_error "Remote upload FAILED. Local backup is preserved."
    fi
}

# ---- List current backups ----
list_backups() {
    local target_dir
    if [ "$METHOD" = "rsync" ] && [ -n "$BACKUP_FOLDER" ]; then
        target_dir="$BACKUP_FOLDER"
    elif [ -n "$ARCHIVE_FOLDER" ]; then
        target_dir="$ARCHIVE_FOLDER"
    else
        return
    fi
    log_info "Current backups in $target_dir:"
    echo ""
    ls -lh "$target_dir" 2>/dev/null | head -20
    echo ""
}

# ---- Confirmation ----
confirm() {
    echo ""
    echo "================================================="
    echo "  Backup Configuration Summary"
    echo "================================================="
    echo "  Method:        $METHOD"
    echo "  Source:        ${SOURCE:-<not set>}"
    echo "  Backup folder: ${BACKUP_FOLDER:-<not set>}"
    echo "  Archive folder: ${ARCHIVE_FOLDER:-<not set>}"
    echo "  Retention:     ${RETENTION_DAYS} days"
    echo "  Remote:        ${REMOTE_ENABLED} ${REMOTE_DEST}"
    echo "  Dry-run:       $DRY_RUN"
    echo "================================================="
    echo ""
    if [ "$DRY_RUN" = false ]; then
        read -p "Proceed with backup? (y/n) " choice
        if [[ "$choice" != "y" ]]; then
            echo "Backup cancelled."
            exit 0
        fi
    fi
}

# =============================================================
# Main
# =============================================================
main() {
    echo ""
    echo "================================================="
    echo "  copia-segura — Safe Backup Tool"
    echo "  $(timestamp)"
    echo "================================================="
    echo ""

    check_deps
    confirm

    log_info "=== Backup job started (METHOD=$METHOD) ==="

    # Validate destination directories exist or can be created
    if [ -n "$ARCHIVE_FOLDER" ]; then
        mkdir -p "$ARCHIVE_FOLDER" 2>/dev/null
        check_disk_space "$ARCHIVE_FOLDER" || exit 1
    fi
    if [ -n "$BACKUP_FOLDER" ] && [ "$METHOD" = "rsync" ]; then
        mkdir -p "$BACKUP_FOLDER" 2>/dev/null
        check_disk_space "$BACKUP_FOLDER" || exit 1
    fi

    # Phase 1 & 2: Execute backup
    run_backup || exit 1

    # Phase 4: Verify integrity
    verify_backup

    # Phase 4: Rotate old backups
    rotate_backups

    # Phase 3: Remote upload
    remote_upload

    # List current backups
    list_backups

    log_info "=== Backup job completed ==="
    echo ""
}

main
