#!/bin/bash
# =============================================================================
# run_backup.sh
# Wrapper script for SQL Server backups via Ola Hallengren
# Handles error detection and email notification on failure
# =============================================================================
# Usage:
#   ./run_backup.sh FULL     # Run full backup of all user databases
#   ./run_backup.sh LOG      # Run transaction log backup of all user databases
# =============================================================================

set -uo pipefail

BACKUP_TYPE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="/etc/sqlbackup/backup.conf"
LOG_DIR="/var/log/sqlbackup"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# --- Validate arguments ------------------------------------------------------
if [[ "$BACKUP_TYPE" != "FULL" && "$BACKUP_TYPE" != "LOG" && "$BACKUP_TYPE" != "CHECKDB" ]]; then
    echo "Usage: $0 FULL|LOG|CHECKDB"
    exit 1
fi

# --- Load configuration ------------------------------------------------------
if [[ ! -f "$CONF_FILE" ]]; then
    echo "ERROR: Config file not found: $CONF_FILE"
    exit 1
fi

# shellcheck source=/dev/null
source "$CONF_FILE"

# --- Ensure required variables are set ----------------------------------------
: "${SQL_USER:?SQL_USER not set in $CONF_FILE}"
: "${SQL_PASSWORD:?SQL_PASSWORD not set in $CONF_FILE}"
: "${SQL_HOST:=localhost}"
: "${BACKUP_DIR:=/mnt/sqlbackups}"
: "${MAIL_PROFILE:=BackupAlerts}"
: "${MAIL_RECIPIENTS:=alerts@example.com}"
: "${CERT_NAME:=}"

# --- Setup logging ------------------------------------------------------------
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/backup_${BACKUP_TYPE}_${TIMESTAMP}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# --- Determine server IP ------------------------------------------------------
SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP="$(hostname)"
fi
SERVER_NAME="$(hostname -f 2>/dev/null || hostname)"

# ==============================================================================
# Functions
# ==============================================================================

# --- Send failure notification via Database Mail ------------------------------
send_failure_notification() {
    log "Sending failure notification to $MAIL_RECIPIENTS"

    # Query CommandLog for the most recent error details
    local ERROR_DETAILS
    ERROR_DETAILS=$(/opt/mssql-tools18/bin/sqlcmd \
        -S "$SQL_HOST" \
        -U "$SQL_USER" \
        -P "$SQL_PASSWORD" \
        -d master \
        -C \
        -h -1 \
        -W \
        -Q "SET NOCOUNT ON;
            SELECT TOP 5
                'Database: ' + ISNULL(DatabaseName, 'N/A')
                + CHAR(13) + CHAR(10)
                + 'Command: ' + LEFT(ISNULL(Command, 'N/A'), 200)
                + CHAR(13) + CHAR(10)
                + 'Error: ' + ISNULL(CAST(ErrorNumber AS VARCHAR) + ' - ' + ErrorMessage, 'N/A')
                + CHAR(13) + CHAR(10)
                + 'Start: ' + ISNULL(CONVERT(VARCHAR, StartTime, 120), 'N/A')
                + CHAR(13) + CHAR(10)
                + 'End: ' + ISNULL(CONVERT(VARCHAR, EndTime, 120), 'N/A')
                + CHAR(13) + CHAR(10)
                + '---'
            FROM dbo.CommandLog
            WHERE (CommandType LIKE 'BACKUP%' OR CommandType LIKE 'DBCC_CHECKDB%')
              AND ErrorNumber <> 0
            ORDER BY ID DESC;" 2>/dev/null) || true

    if [[ -z "$ERROR_DETAILS" ]]; then
        ERROR_DETAILS="No error details found in CommandLog. Check the log file: $LOG_FILE"
    fi

    # Escape single quotes for safe SQL string embedding
    ERROR_DETAILS="${ERROR_DETAILS//\'/\'\'}"
    local SAFE_OUTPUT
    SAFE_OUTPUT="$(echo "$BACKUP_OUTPUT" | tail -50)"
    SAFE_OUTPUT="${SAFE_OUTPUT//\'/\'\'}"

    local EMAIL_SUBJECT="BACKUP FAILURE [$BACKUP_TYPE] on $SERVER_NAME ($SERVER_IP)"
    local EMAIL_BODY
    EMAIL_BODY="SQL Server Backup Failure Report
==================================

Server:      $SERVER_NAME
Server IP:   $SERVER_IP
Backup Type: $BACKUP_TYPE
Time:        $(date '+%Y-%m-%d %H:%M:%S')
Log File:    $LOG_FILE

Error Details:
--------------
$ERROR_DETAILS

sqlcmd Output:
--------------
$SAFE_OUTPUT"

    # Send via Database Mail
    /opt/mssql-tools18/bin/sqlcmd \
        -S "$SQL_HOST" \
        -U "$SQL_USER" \
        -P "$SQL_PASSWORD" \
        -d msdb \
        -C \
        -Q "EXEC sp_send_dbmail
                @profile_name = '$MAIL_PROFILE',
                @recipients   = '$MAIL_RECIPIENTS',
                @subject      = N'$EMAIL_SUBJECT',
                @body         = N'$EMAIL_BODY',
                @body_format  = 'TEXT';" 2>&1 | tee -a "$LOG_FILE" || {
        log "WARNING: Failed to send email notification via Database Mail"
    }
}

# --- Check minimum backup count per database ----------------------------------
check_minimum_backups() {
    log "Checking minimum backup counts..."

    local MIN_COUNT=2
    local ALERT_DATABASES=""

    for DB_DIR in "$BACKUP_DIR"/*/; do
        [[ -d "$DB_DIR" ]] || continue
        local DB_NAME
        DB_NAME="$(basename "$DB_DIR")"

        # Count .bak files (Ola's default extension for full backups)
        local BAK_COUNT
        BAK_COUNT=$(find "$DB_DIR" -maxdepth 2 -name "*.bak" -type f 2>/dev/null | wc -l)

        if [[ $BAK_COUNT -lt $MIN_COUNT ]]; then
            log "WARNING: $DB_NAME has only $BAK_COUNT full backup(s) (minimum: $MIN_COUNT)"
            ALERT_DATABASES="${ALERT_DATABASES}  - $DB_NAME: $BAK_COUNT backup(s)\n"
        fi
    done

    if [[ -n "$ALERT_DATABASES" ]]; then
        local EMAIL_SUBJECT="BACKUP WARNING: Low backup count on $SERVER_NAME ($SERVER_IP)"
        local EMAIL_BODY
        EMAIL_BODY="SQL Server Backup Warning
=========================

Server:    $SERVER_NAME
Server IP: $SERVER_IP
Time:      $(date '+%Y-%m-%d %H:%M:%S')

The following databases have fewer than $MIN_COUNT full backups:
$(echo -e "$ALERT_DATABASES")
Please investigate. Backups may have been manually deleted or failing."

        /opt/mssql-tools18/bin/sqlcmd \
            -S "$SQL_HOST" \
            -U "$SQL_USER" \
            -P "$SQL_PASSWORD" \
            -d msdb \
            -C \
            -Q "EXEC sp_send_dbmail
                    @profile_name = '$MAIL_PROFILE',
                    @recipients   = '$MAIL_RECIPIENTS',
                    @subject      = N'$EMAIL_SUBJECT',
                    @body         = N'$EMAIL_BODY',
                    @body_format  = 'TEXT';" 2>&1 | tee -a "$LOG_FILE" || {
            log "WARNING: Failed to send low-backup-count email"
        }
    else
        log "All databases have at least $MIN_COUNT full backups"
    fi
}

# ==============================================================================
# Main
# ==============================================================================

log "=== Starting $BACKUP_TYPE backup ==="
log "Server: $SERVER_NAME ($SERVER_IP)"

# --- Select SQL script --------------------------------------------------------
case "$BACKUP_TYPE" in
    FULL)    SQL_SCRIPT="${SCRIPT_DIR}/03_backup_full.sql" ;;
    LOG)     SQL_SCRIPT="${SCRIPT_DIR}/04_backup_log.sql" ;;
    CHECKDB) SQL_SCRIPT="${SCRIPT_DIR}/06_checkdb.sql" ;;
esac

if [[ ! -f "$SQL_SCRIPT" ]]; then
    log "ERROR: SQL script not found: $SQL_SCRIPT"
    exit 1
fi

# --- Ensure backup directories exist ------------------------------------------
# Ola Hallengren's DirectoryStructure = '{DatabaseName}/{BackupType}' expects
# subdirectories to already exist.  CIFS/SMB mounts do not allow SQL Server to
# create them on the fly, so we pre-create them here.
if [[ "$BACKUP_TYPE" == "FULL" || "$BACKUP_TYPE" == "LOG" ]]; then
    DB_LIST=$(/opt/mssql-tools18/bin/sqlcmd \
        -S "$SQL_HOST" \
        -U "$SQL_USER" \
        -P "$SQL_PASSWORD" \
        -d master \
        -h -1 \
        -W \
        -C \
        -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 AND state = 0;" 2>/dev/null) || true

    if [[ -n "$DB_LIST" ]]; then
        while IFS= read -r DB_NAME; do
            DB_NAME="$(echo "$DB_NAME" | xargs)"   # trim whitespace
            [[ -z "$DB_NAME" ]] && continue
            mkdir -p "${BACKUP_DIR}/${DB_NAME}/FULL" "${BACKUP_DIR}/${DB_NAME}/LOG"
        done <<< "$DB_LIST"
        log "Ensured backup directories exist for all user databases"
    else
        log "WARNING: Could not query database list - backup directories not pre-created"
    fi
fi

# --- Run backup ---------------------------------------------------------------
BACKUP_EXIT=0
BACKUP_OUTPUT=""

log "Running: $SQL_SCRIPT"

BACKUP_OUTPUT=$(/opt/mssql-tools18/bin/sqlcmd \
    -S "$SQL_HOST" \
    -U "$SQL_USER" \
    -P "$SQL_PASSWORD" \
    -d master \
    -i "$SQL_SCRIPT" \
    -v CERT_NAME="$CERT_NAME" \
    -b \
    -C 2>&1) || BACKUP_EXIT=$?

echo "$BACKUP_OUTPUT" >> "$LOG_FILE"

# --- Handle result ------------------------------------------------------------
if [[ $BACKUP_EXIT -ne 0 ]]; then
    log "BACKUP FAILED with exit code $BACKUP_EXIT"
    send_failure_notification
else
    log "Backup completed successfully"

    # Safety check: ensure at least 2 full backups exist per database
    if [[ "$BACKUP_TYPE" == "FULL" ]]; then
        check_minimum_backups
    fi
fi

log "=== Backup $BACKUP_TYPE finished ==="
exit $BACKUP_EXIT
