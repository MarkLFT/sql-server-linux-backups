#!/bin/bash
# =============================================================================
# setup_cron.sh
# Installs cron entries for SQL Server backup and integrity check jobs
# =============================================================================
# Run as root: sudo ./setup_cron.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="/opt/sqlbackup"
LOG_DIR="/var/log/sqlbackup"
CRON_FILE="/etc/cron.d/sqlbackup"

# Verify scripts exist
for SCRIPT in run_backup.sh 03_backup_full.sql 04_backup_log.sql 06_checkdb.sql; do
    if [[ ! -f "${SCRIPT_DIR}/${SCRIPT}" ]]; then
        echo "ERROR: ${SCRIPT_DIR}/${SCRIPT} not found."
        echo "Copy scripts to ${SCRIPT_DIR}/ first."
        exit 1
    fi
done

# Create log directory
mkdir -p "$LOG_DIR"

# Install cron entries
cat > "$CRON_FILE" << 'EOF'
# SQL Server Backup Jobs - Managed by setup_cron.sh
# Do not edit manually; re-run setup_cron.sh to regenerate.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# DBCC CHECKDB - Wednesday at 03:00 (before the 05:00 full backup)
0 3 * * 3 root /opt/sqlbackup/run_backup.sh CHECKDB >> /var/log/sqlbackup/cron_checkdb.log 2>&1

# Full backup - Daily at 05:00
0 5 * * * root /opt/sqlbackup/run_backup.sh FULL >> /var/log/sqlbackup/cron_full.log 2>&1

# Transaction log backup - Every hour (skips 05:00 to avoid overlap with full)
0 0-4,6-23 * * * root /opt/sqlbackup/run_backup.sh LOG >> /var/log/sqlbackup/cron_log.log 2>&1
EOF

chmod 644 "$CRON_FILE"

echo "[OK] Cron jobs installed to $CRON_FILE"
echo ""
echo "Schedule:"
echo "  CHECKDB:  Wednesday 03:00"
echo "  FULL:     Daily 05:00"
echo "  LOG:      Hourly (except 05:00)"
echo ""
echo "Logs: $LOG_DIR/"
echo ""
echo "Verify with: cat $CRON_FILE"
