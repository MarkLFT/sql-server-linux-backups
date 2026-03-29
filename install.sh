#!/bin/bash
# =============================================================================
# install.sh
# Single-server installer for SQL Server backup automation
# =============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<org>/sqlbackups/master/install.sh | sudo bash
#
# Or download and run:
#   chmod +x install.sh && sudo ./install.sh
# =============================================================================

set -euo pipefail

# --- Colours and formatting ---------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

banner()  { echo -e "\n${CYAN}${BOLD}=== $* ===${NC}\n"; }
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }

# --- Root check ---------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)."
    exit 1
fi

# --- Interactive check --------------------------------------------------------
if [[ ! -t 0 ]]; then
    err "This script requires interactive input."
    err "Download it first, then run it:"
    err "  curl -fsSL <url> -o install.sh && chmod +x install.sh && sudo ./install.sh"
    exit 1
fi

# =============================================================================
# Paths
# =============================================================================
INSTALL_DIR="/opt/sqlbackup"
CONF_DIR="/etc/sqlbackup"
CONF_FILE="${CONF_DIR}/backup.conf"
LOG_DIR="/var/log/sqlbackup"
BACKUP_MOUNT="/mnt/sqlbackups"
SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
CRON_FILE="/etc/cron.d/sqlbackup"
OLA_URL="https://raw.githubusercontent.com/olahallengren/sql-server-maintenance-solution/master/MaintenanceSolution.sql"
TEMP_DIR="$(mktemp -d /tmp/sqlbackup-install.XXXXXX)"

cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

# =============================================================================
# Helper: prompt with default
# =============================================================================
prompt() {
    local var_name="$1" prompt_text="$2" default="${3:-}" is_secret="${4:-}"
    local value

    if [[ -n "$default" && -z "$is_secret" ]]; then
        read -rp "  $prompt_text [$default]: " value
        value="${value:-$default}"
    elif [[ -n "$is_secret" ]]; then
        read -rsp "  $prompt_text: " value
        echo
        if [[ -z "$value" ]]; then
            err "This field is required."
            read -rsp "  $prompt_text: " value
            echo
        fi
    else
        read -rp "  $prompt_text: " value
    fi

    if [[ -z "$value" && -z "$default" ]]; then
        err "This field is required."
        read -rp "  $prompt_text: " value
    fi

    printf -v "$var_name" '%s' "${value:-$default}"
}

prompt_yesno() {
    local prompt_text="$1" default="${2:-y}"
    local value
    read -rp "  $prompt_text [${default}]: " value
    value="${value:-$default}"
    [[ "$value" =~ ^[Yy] ]]
}

# =============================================================================
# Welcome
# =============================================================================
echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║       SQL Server Backup Automation - Installer           ║"
echo "  ║       Ola Hallengren + Encrypted Backups + Alerts        ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  This script will:"
echo "    1. Install Ola Hallengren's Maintenance Solution"
echo "    2. Create a dedicated backup_admin SQL login"
echo "    3. Configure Database Mail for failure alerts"
echo "    4. Deploy backup/integrity-check scripts"
echo "    5. Create configuration and cron jobs"
echo ""
echo -e "  ${YELLOW}You will need: SA password, SMTP credentials, alert email${NC}"
echo ""

if ! prompt_yesno "Continue with installation?" "y"; then
    echo "Aborted."
    exit 0
fi

# =============================================================================
# Step 1: Prerequisites
# =============================================================================
banner "Step 1/7: Checking Prerequisites"

# sqlcmd
if [[ -x "$SQLCMD" ]]; then
    ok "sqlcmd found at $SQLCMD"
else
    err "sqlcmd not found at $SQLCMD"
    err "Install mssql-tools18 first:"
    err "  https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools"
    exit 1
fi

# curl
if command -v curl &>/dev/null; then
    ok "curl available"
else
    err "curl is required but not installed."
    exit 1
fi

# Check SQL Server is running
if "$SQLCMD" -S localhost -Q "SELECT 1" -C -b &>/dev/null 2>&1; then
    ok "SQL Server is reachable on localhost"
else
    warn "Could not connect to SQL Server on localhost (may need credentials)"
fi

# =============================================================================
# Step 2: Gather Information
# =============================================================================
banner "Step 2/7: Configuration"

echo -e "  ${BOLD}SQL Server Connection${NC}"
prompt SA_PASSWORD    "SA password (for initial setup)" "" "secret"
prompt SQL_HOST       "SQL Server host"                 "localhost"

echo ""
echo -e "  ${BOLD}Backup Admin Login${NC} (will be created)"
prompt BACKUP_USER    "Backup SQL login name"           "backup_admin"
prompt BACKUP_PASS    "Backup SQL login password"       "" "secret"

echo ""
echo -e "  ${BOLD}Backup Storage${NC}"
prompt BACKUP_DIR     "Backup directory"                "$BACKUP_MOUNT"

echo ""
echo -e "  ${BOLD}Backup Schedule${NC}"
prompt FULL_BACKUP_HOUR "Full backup hour (0-23, 24h format)" "5"
prompt LOG_FREQ_MINUTES "Transaction log backup frequency in minutes (15/30/60)" "60"

# Validate full backup hour
if ! [[ "$FULL_BACKUP_HOUR" =~ ^[0-9]+$ ]] || [[ "$FULL_BACKUP_HOUR" -gt 23 ]]; then
    err "Invalid hour '$FULL_BACKUP_HOUR' - must be 0-23"
    exit 1
fi

# Validate log frequency
case "$LOG_FREQ_MINUTES" in
    15|30|60) ;;
    *)
        err "Invalid log frequency '$LOG_FREQ_MINUTES' - must be 15, 30, or 60"
        exit 1
        ;;
esac

echo ""
echo -e "  ${BOLD}SMTP / Email Alerts${NC}"
prompt SMTP_SERVER    "SMTP server"                     "smtp.example.com"
prompt SMTP_PORT      "SMTP port"                       "587"
prompt SMTP_USER      "SMTP username"                   ""
prompt SMTP_PASS      "SMTP password"                   "" "secret"
prompt SENDER_EMAIL   "Sender (From) email"             ""
prompt ALERT_EMAIL    "Alert recipient email"           ""

ENABLE_SSL=1
if ! prompt_yesno "Enable TLS/SSL for SMTP?" "y"; then
    ENABLE_SSL=0
fi

echo ""
echo -e "  ${BOLD}Mail Profile${NC}"
prompt MAIL_PROFILE   "Database Mail profile name"      "BackupAlerts"

# =============================================================================
# Step 3: Create Directories
# =============================================================================
banner "Step 3/7: Creating Directories"

for DIR in "$INSTALL_DIR" "$CONF_DIR" "$LOG_DIR"; do
    mkdir -p "$DIR"
    ok "Created $DIR"
done

if [[ -d "$BACKUP_DIR" ]]; then
    ok "$BACKUP_DIR already exists"
else
    mkdir -p "$BACKUP_DIR"
    ok "Created $BACKUP_DIR"
fi

# Set ownership - mssql user needs write access to backup dir
if id mssql &>/dev/null; then
    chown mssql:mssql "$BACKUP_DIR"
    chmod 0750 "$BACKUP_DIR"
    ok "Set $BACKUP_DIR ownership to mssql:mssql (0750)"
else
    warn "mssql user not found - set backup directory permissions manually"
fi

chmod 0700 "$CONF_DIR"

# =============================================================================
# Step 4: Install Ola Hallengren
# =============================================================================
banner "Step 4/7: Installing Ola Hallengren Maintenance Solution"

info "Downloading MaintenanceSolution.sql..."
if curl -fsSL "$OLA_URL" -o "${TEMP_DIR}/MaintenanceSolution.sql"; then
    ok "Downloaded MaintenanceSolution.sql"
else
    err "Failed to download Ola Hallengren's Maintenance Solution"
    err "URL: $OLA_URL"
    exit 1
fi

info "Installing into master database..."
if "$SQLCMD" -S "$SQL_HOST" -U SA -P "$SA_PASSWORD" -d master \
    -i "${TEMP_DIR}/MaintenanceSolution.sql" -b -C &>"${TEMP_DIR}/ola_install.log"; then
    ok "Ola Hallengren installed successfully"
else
    err "Failed to install Ola Hallengren. Log:"
    tail -20 "${TEMP_DIR}/ola_install.log"
    exit 1
fi

# Verify
info "Verifying installation..."
VERIFY_RESULT=$("$SQLCMD" -S "$SQL_HOST" -U SA -P "$SA_PASSWORD" -d master -C -h -1 -W -Q "
    SET NOCOUNT ON;
    SELECT CASE WHEN
        OBJECT_ID('dbo.DatabaseBackup','P') IS NOT NULL AND
        OBJECT_ID('dbo.DatabaseIntegrityCheck','P') IS NOT NULL AND
        OBJECT_ID('dbo.CommandLog','U') IS NOT NULL
    THEN 'PASS' ELSE 'FAIL' END;" 2>/dev/null | tr -d '[:space:]')

if [[ "$VERIFY_RESULT" == "PASS" ]]; then
    ok "Verified: DatabaseBackup, DatabaseIntegrityCheck, CommandLog all present"
else
    err "Verification failed - some Ola Hallengren objects are missing"
    exit 1
fi

# --- Auto-detect TDE certificate ----------------------------------------------
info "Detecting TDE certificate..."
CERT_NAME=$("$SQLCMD" -S "$SQL_HOST" -U SA -P "$SA_PASSWORD" -d master -C -h -1 -W -Q "
    SET NOCOUNT ON;
    SELECT TOP 1 c.name
    FROM sys.dm_database_encryption_keys dek
    JOIN sys.certificates c ON dek.encryptor_thumbprint = c.thumbprint
    WHERE dek.database_id > 4;" 2>/dev/null | tr -d '[:space:]') || true

if [[ -n "$CERT_NAME" ]]; then
    ok "TDE certificate detected: $CERT_NAME"
else
    warn "No TDE certificate found - backups will auto-detect at runtime"
    CERT_NAME=""
fi

# =============================================================================
# Step 5: Create backup_admin Login & Configure Database Mail
# =============================================================================
banner "Step 5/7: SQL Server Configuration"

# --- Create backup_admin login ------------------------------------------------
info "Creating SQL login '$BACKUP_USER'..."

# Escape single quotes in password for T-SQL
ESCAPED_BACKUP_PASS="${BACKUP_PASS//\'/\'\'}"

"$SQLCMD" -S "$SQL_HOST" -U SA -P "$SA_PASSWORD" -d master -b -C -Q "
    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$BACKUP_USER')
    BEGIN
        CREATE LOGIN [$BACKUP_USER] WITH PASSWORD = N'$ESCAPED_BACKUP_PASS', CHECK_POLICY = OFF;
        ALTER SERVER ROLE [sysadmin] ADD MEMBER [$BACKUP_USER];
        PRINT '[OK] Login $BACKUP_USER created with sysadmin role';
    END
    ELSE
    BEGIN
        PRINT '[OK] Login $BACKUP_USER already exists';
    END
" 2>&1 | grep -E '^\[' || true
ok "SQL login configured"

# --- Configure Database Mail --------------------------------------------------
info "Configuring Database Mail..."

ESCAPED_SMTP_PASS="${SMTP_PASS//\'/\'\'}"

cat > "${TEMP_DIR}/configure_mail.sql" << EOSQL
USE [msdb];
GO

EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Database Mail XPs', 1;
RECONFIGURE;

-- Drop existing profile/account if re-running
IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profileaccount pa
           JOIN msdb.dbo.sysmail_profile p ON pa.profile_id = p.profile_id
           JOIN msdb.dbo.sysmail_account a ON pa.account_id = a.account_id
           WHERE p.name = N'${MAIL_PROFILE}' AND a.name = N'BackupSMTP')
BEGIN
    EXEC msdb.dbo.sysmail_delete_profileaccount_sp
        @profile_name = N'${MAIL_PROFILE}',
        @account_name = N'BackupSMTP';
END

IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = N'${MAIL_PROFILE}')
    EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = N'${MAIL_PROFILE}';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_account WHERE name = N'BackupSMTP')
    EXEC msdb.dbo.sysmail_delete_account_sp @account_name = N'BackupSMTP';

EXEC msdb.dbo.sysmail_add_account_sp
    @account_name   = N'BackupSMTP',
    @description    = N'SMTP account for SQL Server backup alerts',
    @email_address  = N'${SENDER_EMAIL}',
    @display_name   = N'SQL Backup Alerts',
    @mailserver_name = N'${SMTP_SERVER}',
    @port           = ${SMTP_PORT},
    @username       = N'${SMTP_USER}',
    @password       = N'${ESCAPED_SMTP_PASS}',
    @enable_ssl     = ${ENABLE_SSL};

EXEC msdb.dbo.sysmail_add_profile_sp
    @profile_name = N'${MAIL_PROFILE}',
    @description  = N'Profile for sending backup failure notifications';

EXEC msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name    = N'${MAIL_PROFILE}',
    @account_name    = N'BackupSMTP',
    @sequence_number = 1;

EXEC msdb.dbo.sysmail_add_principalsecurity_sp
    @profile_name    = N'${MAIL_PROFILE}',
    @principal_name  = N'public',
    @is_default      = 1;

EXEC msdb.dbo.sp_send_dbmail
    @profile_name = N'${MAIL_PROFILE}',
    @recipients   = N'${ALERT_EMAIL}',
    @subject      = N'SQL Server Backup Alerts - Test Email',
    @body         = N'This is a test email from SQL Server Database Mail. If you received this, backup notifications are configured correctly.',
    @body_format  = N'TEXT';
GO
EOSQL

if "$SQLCMD" -S "$SQL_HOST" -U SA -P "$SA_PASSWORD" \
    -i "${TEMP_DIR}/configure_mail.sql" -b -C &>"${TEMP_DIR}/mail_setup.log"; then
    ok "Database Mail configured"
    info "Test email sent to $ALERT_EMAIL - check your inbox"
else
    warn "Database Mail configuration had errors (check ${TEMP_DIR}/mail_setup.log)"
    warn "You can re-configure manually later with 02_configure_database_mail.sql"
fi

# =============================================================================
# Step 6: Deploy Scripts & Configuration
# =============================================================================
banner "Step 6/7: Deploying Scripts"

# --- Write SQL scripts inline (matching the project versions) -----------------

# 03_backup_full.sql
cat > "${INSTALL_DIR}/03_backup_full.sql" << 'EOSQL'
USE [master];
GO

DECLARE @cert_name NVARCHAR(128);

SET @cert_name = N'$(CERT_NAME)';

IF @cert_name = N'' OR @cert_name = N'$(CERT_NAME)'
BEGIN
    SELECT TOP 1 @cert_name = c.name
    FROM sys.dm_database_encryption_keys dek
    JOIN sys.certificates c ON dek.encryptor_thumbprint = c.thumbprint
    WHERE dek.database_id > 4;

    IF @cert_name IS NULL
    BEGIN
        RAISERROR('No TDE certificate found. Cannot encrypt backups.', 16, 1);
        RETURN;
    END
END

PRINT 'Using TDE certificate: ' + @cert_name;

EXEC dbo.DatabaseBackup
    @Databases          = 'USER_DATABASES',
    @Directory          = '/mnt/sqlbackups',
    @BackupType         = 'FULL',
    @Compress           = 'Y',
    @MaxTransferSize    = 4194304,
    @Encrypt            = 'Y',
    @EncryptionAlgorithm = 'AES_256',
    @ServerCertificate  = @cert_name,
    @CleanupTime        = 168,
    @CleanupMode        = 'AFTER_BACKUP',
    @LogToTable         = 'Y',
    @DirectoryStructure = '{DatabaseName}/{BackupType}',
    @FileName           = '{DatabaseName}_FULL_{Year}{Month}{Day}_{Hour}{Minute}{Second}.{FileExtension}';
GO
EOSQL

# Patch backup directory if non-default
if [[ "$BACKUP_DIR" != "/mnt/sqlbackups" ]]; then
    sed -i "s|@Directory          = '/mnt/sqlbackups'|@Directory          = '${BACKUP_DIR}'|g" "${INSTALL_DIR}/03_backup_full.sql"
fi

# 04_backup_log.sql (only targets databases in FULL recovery model)
cat > "${INSTALL_DIR}/04_backup_log.sql" << 'EOSQL'
USE [master];
GO

DECLARE @db_list NVARCHAR(MAX) = N'';

SELECT @db_list = @db_list + QUOTENAME(name) + N','
FROM sys.databases
WHERE database_id > 4
  AND state = 0
  AND recovery_model = 1;

SET @db_list = LEFT(@db_list, LEN(@db_list) - 1);

IF @db_list = N''
BEGIN
    PRINT 'No user databases in FULL recovery model - skipping log backup.';
    RETURN;
END

PRINT 'Log backup targets: ' + @db_list;

EXEC dbo.DatabaseBackup
    @Databases          = @db_list,
    @Directory          = '/mnt/sqlbackups',
    @BackupType         = 'LOG',
    @Compress           = 'Y',
    @MaxTransferSize    = 4194304,
    @CleanupTime        = 48,
    @CleanupMode        = 'AFTER_BACKUP',
    @LogToTable         = 'Y',
    @DirectoryStructure = '{DatabaseName}/{BackupType}',
    @FileName           = '{DatabaseName}_LOG_{Year}{Month}{Day}_{Hour}{Minute}{Second}.{FileExtension}';
GO
EOSQL

if [[ "$BACKUP_DIR" != "/mnt/sqlbackups" ]]; then
    sed -i "s|@Directory          = '/mnt/sqlbackups'|@Directory          = '${BACKUP_DIR}'|g" "${INSTALL_DIR}/04_backup_log.sql"
fi

# 06_checkdb.sql
cat > "${INSTALL_DIR}/06_checkdb.sql" << 'EOSQL'
USE [master];
GO

EXEC dbo.DatabaseIntegrityCheck
    @Databases = 'USER_DATABASES',
    @LogToTable = 'Y';
GO
EOSQL

# 05_verify_setup.sql
cat > "${INSTALL_DIR}/05_verify_setup.sql" << 'EOSQL'
USE [master];
GO

PRINT '==========================================================';
PRINT '  SQL Server Backup Setup - Verification Report';
PRINT '==========================================================';
PRINT '';

PRINT '--- Ola Hallengren Objects ---';

IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL
    PRINT '[OK]   dbo.DatabaseBackup';
ELSE
    PRINT '[FAIL] dbo.DatabaseBackup - NOT FOUND';

IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL
    PRINT '[OK]   dbo.DatabaseIntegrityCheck';
ELSE
    PRINT '[FAIL] dbo.DatabaseIntegrityCheck - NOT FOUND';

IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL
    PRINT '[OK]   dbo.CommandLog table';
ELSE
    PRINT '[FAIL] dbo.CommandLog table - NOT FOUND';

PRINT '';

PRINT '--- Database Mail ---';

DECLARE @mail_enabled INT;
SELECT @mail_enabled = CAST(value_in_use AS INT)
FROM sys.configurations
WHERE name = 'Database Mail XPs';

IF @mail_enabled = 1
    PRINT '[OK]   Database Mail XPs enabled';
ELSE
    PRINT '[FAIL] Database Mail XPs not enabled';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = 'BackupAlerts')
    PRINT '[OK]   Mail profile "BackupAlerts" exists';
ELSE
    PRINT '[FAIL] Mail profile "BackupAlerts" - NOT FOUND';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_account)
    PRINT '[OK]   Mail account configured';
ELSE
    PRINT '[FAIL] No mail accounts configured';

PRINT '';

PRINT '--- User Databases ---';
SELECT
    LEFT(name, 30) AS [Database],
    LEFT(recovery_model_desc, 8) AS [Recovery],
    LEFT(state_desc, 8) AS [State]
FROM sys.databases
WHERE database_id > 4
ORDER BY name;

PRINT '';

PRINT '--- TDE Certificate ---';
IF EXISTS (
    SELECT 1 FROM sys.dm_database_encryption_keys dek
    JOIN sys.certificates c ON dek.encryptor_thumbprint = c.thumbprint
    WHERE dek.database_id > 4
)
BEGIN
    SELECT
        LEFT(c.name, 20) AS [Certificate],
        c.expiry_date AS [Expiry],
        LEFT(d.name, 20) AS [Database]
    FROM sys.dm_database_encryption_keys dek
    JOIN sys.certificates c ON dek.encryptor_thumbprint = c.thumbprint
    JOIN sys.databases d ON dek.database_id = d.database_id
    WHERE dek.database_id > 4;
END
ELSE
    PRINT '[WARN] No TDE certificates found - backup encryption will fail';

PRINT '';

PRINT '--- Recent CommandLog Entries (last 10) ---';
IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL
BEGIN
    SELECT TOP 10
        ID,
        LEFT(DatabaseName, 20) AS [Database],
        LEFT(CommandType, 15) AS [Type],
        LEFT(CASE WHEN ErrorNumber = 0 THEN 'OK' ELSE 'FAIL: ' + ISNULL(ErrorMessage, '') END, 30) AS [Result],
        StartTime,
        EndTime
    FROM dbo.CommandLog
    ORDER BY ID DESC;
END
ELSE
    PRINT 'CommandLog table not found.';

PRINT '';

PRINT '--- Recent Backup History (last 10) ---';
SELECT TOP 10
    LEFT(bs.database_name, 20) AS [Database],
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'L' THEN 'Log'
        WHEN 'I' THEN 'Diff'
    END AS [Type],
    bs.backup_finish_date AS [Completed],
    CAST(bs.compressed_backup_size / 1048576.0 AS DECIMAL(10,2)) AS [Size (MB)],
    LEFT(bmf.physical_device_name, 50) AS [File]
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
ORDER BY bs.backup_finish_date DESC;

PRINT '';
PRINT '==========================================================';
PRINT '  Verification complete';
PRINT '==========================================================';
GO
EOSQL

# run_backup.sh
cat > "${INSTALL_DIR}/run_backup.sh" << 'EOSH'
#!/bin/bash
set -uo pipefail

BACKUP_TYPE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="/etc/sqlbackup/backup.conf"
LOG_DIR="/var/log/sqlbackup"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

if [[ "$BACKUP_TYPE" != "FULL" && "$BACKUP_TYPE" != "LOG" && "$BACKUP_TYPE" != "CHECKDB" ]]; then
    echo "Usage: $0 FULL|LOG|CHECKDB"
    exit 1
fi

if [[ ! -f "$CONF_FILE" ]]; then
    echo "ERROR: Config file not found: $CONF_FILE"
    exit 1
fi

source "$CONF_FILE"

: "${SQL_USER:?SQL_USER not set in $CONF_FILE}"
: "${SQL_PASSWORD:?SQL_PASSWORD not set in $CONF_FILE}"
: "${SQL_HOST:=localhost}"
: "${BACKUP_DIR:=/mnt/sqlbackups}"
: "${MAIL_PROFILE:=BackupAlerts}"
: "${MAIL_RECIPIENTS:=alerts@example.com}"
: "${CERT_NAME:=}"

mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/backup_${BACKUP_TYPE}_${TIMESTAMP}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP="$(hostname)"
fi
SERVER_NAME="$(hostname -f 2>/dev/null || hostname)"

send_failure_notification() {
    log "Sending failure notification to $MAIL_RECIPIENTS"

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

check_minimum_backups() {
    log "Checking minimum backup counts..."

    local MIN_COUNT=2
    local ALERT_DATABASES=""

    for DB_DIR in "$BACKUP_DIR"/*/; do
        [[ -d "$DB_DIR" ]] || continue
        local DB_NAME
        DB_NAME="$(basename "$DB_DIR")"

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

log "=== Starting $BACKUP_TYPE backup ==="
log "Server: $SERVER_NAME ($SERVER_IP)"

case "$BACKUP_TYPE" in
    FULL)    SQL_SCRIPT="${SCRIPT_DIR}/03_backup_full.sql" ;;
    LOG)     SQL_SCRIPT="${SCRIPT_DIR}/04_backup_log.sql" ;;
    CHECKDB) SQL_SCRIPT="${SCRIPT_DIR}/06_checkdb.sql" ;;
esac

if [[ ! -f "$SQL_SCRIPT" ]]; then
    log "ERROR: SQL script not found: $SQL_SCRIPT"
    exit 1
fi

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

if [[ $BACKUP_EXIT -ne 0 ]]; then
    log "BACKUP FAILED with exit code $BACKUP_EXIT"
    send_failure_notification
else
    log "Backup completed successfully"

    if [[ "$BACKUP_TYPE" == "FULL" ]]; then
        check_minimum_backups
    fi
fi

log "=== Backup $BACKUP_TYPE finished ==="
exit $BACKUP_EXIT
EOSH

chmod +x "${INSTALL_DIR}/run_backup.sh"
ok "Deployed run_backup.sh"
ok "Deployed 03_backup_full.sql"
ok "Deployed 04_backup_log.sql"
ok "Deployed 06_checkdb.sql"
ok "Deployed 05_verify_setup.sql"

# --- Write backup.conf -------------------------------------------------------
cat > "$CONF_FILE" << EOCONF
# SQL Server Backup Configuration
# Generated by install.sh on $(date '+%Y-%m-%d %H:%M:%S')

SQL_USER="${BACKUP_USER}"
SQL_PASSWORD="${BACKUP_PASS}"
SQL_HOST="${SQL_HOST}"

BACKUP_DIR="${BACKUP_DIR}"

CERT_NAME="${CERT_NAME}"

MAIL_PROFILE="${MAIL_PROFILE}"
MAIL_RECIPIENTS="${ALERT_EMAIL}"
EOCONF

chmod 600 "$CONF_FILE"
ok "Created $CONF_FILE (mode 600)"

# =============================================================================
# Step 7: Cron Jobs
# =============================================================================
banner "Step 7/7: Installing Cron Jobs"

# Build cron schedule from user choices
# CHECKDB runs 2 hours before full backup on Wednesdays
CHECKDB_HOUR=$(( (FULL_BACKUP_HOUR + 22) % 24 ))  # full - 2, wrapping

# Build the log backup skip expression (skip the full backup hour)
if [[ "$LOG_FREQ_MINUTES" == "60" ]]; then
    # Hourly - skip the full backup hour
    if [[ "$FULL_BACKUP_HOUR" -eq 0 ]]; then
        LOG_SCHEDULE="0 1-23 * * *"
    elif [[ "$FULL_BACKUP_HOUR" -eq 23 ]]; then
        LOG_SCHEDULE="0 0-22 * * *"
    else
        LOG_SCHEDULE="0 0-$((FULL_BACKUP_HOUR - 1)),$((FULL_BACKUP_HOUR + 1))-23 * * *"
    fi
elif [[ "$LOG_FREQ_MINUTES" == "30" ]]; then
    LOG_SCHEDULE="0,30 * * * *"
elif [[ "$LOG_FREQ_MINUTES" == "15" ]]; then
    LOG_SCHEDULE="0,15,30,45 * * * *"
fi

cat > "$CRON_FILE" << CRONEOF
# SQL Server Backup Jobs - Managed by install.sh
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# DBCC CHECKDB - Wednesday at ${CHECKDB_HOUR}:00 (before the full backup)
0 ${CHECKDB_HOUR} * * 3 root /opt/sqlbackup/run_backup.sh CHECKDB >> /var/log/sqlbackup/cron_checkdb.log 2>&1

# Full backup - Daily at ${FULL_BACKUP_HOUR}:00
0 ${FULL_BACKUP_HOUR} * * * root /opt/sqlbackup/run_backup.sh FULL >> /var/log/sqlbackup/cron_full.log 2>&1

# Transaction log backup - Every ${LOG_FREQ_MINUTES} minutes
${LOG_SCHEDULE} root /opt/sqlbackup/run_backup.sh LOG >> /var/log/sqlbackup/cron_log.log 2>&1
CRONEOF

chmod 644 "$CRON_FILE"
ok "Cron jobs installed to $CRON_FILE"

# =============================================================================
# Verification
# =============================================================================
banner "Running Verification"

info "Running 05_verify_setup.sql..."
echo ""
"$SQLCMD" -S "$SQL_HOST" -U "$BACKUP_USER" -P "$BACKUP_PASS" -d master \
    -i "${INSTALL_DIR}/05_verify_setup.sql" -C 2>&1 || {
    warn "Verification query had issues - review output above"
}

# =============================================================================
# Initial Full Backup
# =============================================================================
echo ""
echo -e "  ${YELLOW}${BOLD}A full backup must exist before transaction log backups can succeed.${NC}"
echo -e "  The first scheduled cron job is likely a log backup, which will fail"
echo -e "  without an existing full backup."
echo ""

if prompt_yesno "Run an initial full backup now?" "y"; then
    banner "Running Initial Full Backup"
    info "This may take a while depending on database sizes..."
    echo ""
    if "${INSTALL_DIR}/run_backup.sh" FULL; then
        ok "Initial full backup completed successfully"
    else
        warn "Full backup had errors - check ${LOG_DIR}/ for details"
        warn "You can retry manually:  sudo ${INSTALL_DIR}/run_backup.sh FULL"
    fi
else
    echo ""
    warn "Skipped. Run a full backup manually before the first scheduled log backup:"
    echo -e "    sudo ${INSTALL_DIR}/run_backup.sh FULL"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${GREEN}${BOLD}  Installation Complete${NC}"
echo -e "  ${CYAN}─────────────────────────────────────────────${NC}"
echo ""
echo -e "  ${BOLD}Installed Components${NC}"
echo "    Scripts ........... ${INSTALL_DIR}/"
echo "    Configuration ..... ${CONF_FILE}"
echo "    Logs .............. ${LOG_DIR}/"
echo "    Cron .............. ${CRON_FILE}"
echo "    Backup storage .... ${BACKUP_DIR}"
echo "    TDE certificate ... ${CERT_NAME:-auto-detect}"
echo ""
echo -e "  ${BOLD}Cron Schedule${NC}"
echo "    CHECKDB ........... Wednesday $(printf '%02d' "$CHECKDB_HOUR"):00"
echo "    FULL .............. Daily $(printf '%02d' "$FULL_BACKUP_HOUR"):00"
echo "    LOG ............... Every ${LOG_FREQ_MINUTES} min"
echo ""
echo -e "  ${BOLD}Manual Commands${NC}"
echo "    sudo ${INSTALL_DIR}/run_backup.sh FULL"
echo "    sudo ${INSTALL_DIR}/run_backup.sh LOG"
echo "    sudo ${INSTALL_DIR}/run_backup.sh CHECKDB"
echo ""
echo -e "  ${CYAN}─────────────────────────────────────────────${NC}"
echo ""

echo -e "${YELLOW}${BOLD}── Mounting Backup Storage ──${NC}"
echo ""
echo -e "Backups are written to ${BOLD}${BACKUP_DIR}${NC}."
echo "This should be a network share for off-server redundancy."
echo ""
echo -e "${BOLD}SMB/CIFS Mount:${NC}"
echo "  1. Install:     apt install cifs-utils  (or)  yum install cifs-utils"
echo "  2. Credentials: echo -e 'username=<smb_user>\npassword=<smb_pass>\ndomain=<domain>' > /etc/smbcredentials"
echo "                  chmod 600 /etc/smbcredentials"
echo "  3. fstab:       //<server>/<share>  ${BACKUP_DIR}  cifs  credentials=/etc/smbcredentials,uid=mssql,gid=mssql,file_mode=0750,dir_mode=0750,nofail  0  0"
echo "  4. Mount:       mount ${BACKUP_DIR}"
echo ""
echo -e "${BOLD}NFS Mount:${NC}"
echo "  1. Install:     apt install nfs-common  (or)  yum install nfs-utils"
echo "  2. fstab:       <server>:/<export>  ${BACKUP_DIR}  nfs  defaults,nofail  0  0"
echo "  3. Mount:       mount ${BACKUP_DIR}"
echo "  4. Ensure the NFS export allows write access from the mssql uid/gid"
echo ""
echo -e "${YELLOW}Important:${NC} Mount the share ${BOLD}before${NC} the first scheduled backup."
echo "Verify write access:  sudo -u mssql touch ${BACKUP_DIR}/test && rm ${BACKUP_DIR}/test && echo OK"
echo ""

echo -e "This script is safe to re-run. It will update existing components without"
echo -e "duplicating SQL logins or mail profiles."
echo ""
