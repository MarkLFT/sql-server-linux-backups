# SQL Server Backup Solution (Ola Hallengren)

Automated backup solution for SQL Server 2022 on Linux using [Ola Hallengren's Maintenance Solution](https://ola.hallengren.com/). Scheduled via Linux cron for compatibility with all editions including Express.

## Schedule

| Job | Schedule | Retention |
|-----|----------|-----------|
| DBCC CHECKDB | Wednesday 03:00 | N/A |
| Full Backup | Daily 05:00 | 7 days (minimum 2 kept) |
| Transaction Log Backup | Hourly (except 05:00) | 2 days |

## Features

- Full and transaction log backups of all user databases
- Backup encryption using the existing TDE certificate (AES_256)
- Maximum compression (`MAXTRANSFERSIZE = 4194304`)
- Each database backed up to its own folder under `/mnt/sqlbackups/<DatabaseName>/`
- Cleanup only after successful backup (`AFTER_BACKUP` mode)
- Safety check: alerts if any database drops below 2 full backups
- Email notification on failure with server IP, database name, and error details
- Weekly DBCC CHECKDB before the Wednesday full backup

## Prerequisites

1. **SQL Server 2022 on Linux** (any edition)
2. **sqlcmd** installed (`/opt/mssql-tools18/bin/sqlcmd`)
3. **Backup directory** mounted and writable:
   ```bash
   sudo mkdir -p /mnt/sqlbackups
   sudo chown mssql:mssql /mnt/sqlbackups
   ```
4. **All databases in FULL recovery model** (required for transaction log backups)
5. **TDE enabled** on user databases (for backup encryption)
6. **SMTP server credentials** for email notifications

## Quick Start (Manual Deployment)

### Step 1: Find Your TDE Certificate Name

Connect to SQL Server and run:

```sql
SELECT c.name AS CertificateName, d.name AS DatabaseName
FROM sys.dm_database_encryption_keys dek
JOIN sys.certificates c ON dek.encryptor_thumbprint = c.thumbprint
JOIN sys.databases d ON dek.database_id = d.database_id
WHERE dek.database_id > 4;
```

Note the certificate name. The backup scripts auto-detect it, but you can also hardcode it in `backup.conf`.

### Step 2: Install Ola Hallengren

Download and install the maintenance solution:

```bash
# Download latest release
wget https://raw.githubusercontent.com/olahallengren/sql-server-maintenance-solution/master/MaintenanceSolution.sql

# Install into master database
/opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P '<YourPassword>' \
    -i MaintenanceSolution.sql -C

# Verify installation
/opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P '<YourPassword>' \
    -i scripts/01_install_ola_hallengren.sql -C
```

### Step 3: Create a Backup Login

Create a dedicated SQL login for the backup scripts:

```sql
USE [master];
CREATE LOGIN [backup_admin] WITH PASSWORD = '<StrongPassword>';
ALTER SERVER ROLE [sysadmin] ADD MEMBER [backup_admin];
```

### Step 4: Configure Database Mail

Edit `scripts/02_configure_database_mail.sql` and update the SMTP placeholders at the top of the file:

- `@smtp_server` - Your SMTP server hostname
- `@smtp_port` - SMTP port (587 for TLS)
- `@smtp_user` - SMTP username
- `@smtp_password` - SMTP password
- `@sender_email` - From address

Then run it:

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P '<YourPassword>' \
    -i scripts/02_configure_database_mail.sql -C
```

Check your inbox for the test email.

### Step 5: Deploy Scripts

```bash
# Create directories
sudo mkdir -p /opt/sqlbackup /etc/sqlbackup /var/log/sqlbackup

# Copy scripts
sudo cp scripts/run_backup.sh /opt/sqlbackup/
sudo cp scripts/03_backup_full.sql /opt/sqlbackup/
sudo cp scripts/04_backup_log.sql /opt/sqlbackup/
sudo cp scripts/06_checkdb.sql /opt/sqlbackup/
sudo chmod +x /opt/sqlbackup/run_backup.sh

# Create config file
sudo cp scripts/backup.conf.example /etc/sqlbackup/backup.conf
sudo chmod 600 /etc/sqlbackup/backup.conf
```

Edit `/etc/sqlbackup/backup.conf` with your credentials:

```bash
sudo nano /etc/sqlbackup/backup.conf
```

Update `SQL_USER`, `SQL_PASSWORD`, and optionally `CERT_NAME`.

### Step 6: Test Backups

```bash
# Test full backup
sudo /opt/sqlbackup/run_backup.sh FULL

# Test log backup
sudo /opt/sqlbackup/run_backup.sh LOG

# Test CHECKDB
sudo /opt/sqlbackup/run_backup.sh CHECKDB

# Verify files were created
ls -la /mnt/sqlbackups/*/
```

### Step 7: Install Cron Jobs

```bash
sudo ./scripts/setup_cron.sh
```

Or install manually:

```bash
sudo crontab -e
```

Add:

```
# DBCC CHECKDB - Wednesday 03:00
0 3 * * 3 /opt/sqlbackup/run_backup.sh CHECKDB >> /var/log/sqlbackup/cron_checkdb.log 2>&1

# Full backup - Daily 05:00
0 5 * * * /opt/sqlbackup/run_backup.sh FULL >> /var/log/sqlbackup/cron_full.log 2>&1

# Transaction log backup - Hourly (skip 05:00)
0 0-4,6-23 * * * /opt/sqlbackup/run_backup.sh LOG >> /var/log/sqlbackup/cron_log.log 2>&1
```

### Step 8: Verify Everything

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P '<YourPassword>' \
    -i scripts/05_verify_setup.sql -C
```

## Ansible Deployment

For automated deployment across multiple servers:

### Setup

```bash
cd ansible/

# Copy and edit inventory
cp inventory.yml.example inventory.yml
# Edit with your server IPs

# Copy and edit group variables
cp group_vars/sqlservers.yml.example group_vars/sqlservers.yml
# Edit with your SMTP creds, passwords, etc.

# (Recommended) Encrypt secrets with ansible-vault
ansible-vault encrypt_string '<sql_password>' --name 'vault_sql_password'
ansible-vault encrypt_string '<smtp_password>' --name 'vault_smtp_password'
```

### Deploy

```bash
# Deploy to all servers
ansible-playbook -i inventory.yml deploy_backups.yml --ask-vault-pass

# Deploy to a single server
ansible-playbook -i inventory.yml deploy_backups.yml --limit sql-prod-01 --ask-vault-pass

# Dry run
ansible-playbook -i inventory.yml deploy_backups.yml --check
```

## File Structure

```
sqlbackups/
├── README.md                                  # This file
├── scripts/
│   ├── 01_install_ola_hallengren.sql          # Verification after Ola install
│   ├── 02_configure_database_mail.sql         # Database Mail setup
│   ├── 03_backup_full.sql                     # Full backup T-SQL
│   ├── 04_backup_log.sql                      # Transaction log backup T-SQL
│   ├── 05_verify_setup.sql                    # Full verification report
│   ├── 06_checkdb.sql                         # DBCC CHECKDB T-SQL
│   ├── run_backup.sh                          # Bash wrapper (cron calls this)
│   ├── setup_cron.sh                          # Cron job installer
│   └── backup.conf.example                    # Config template
├── ansible/
│   ├── inventory.yml.example                  # Server inventory template
│   ├── group_vars/
│   │   └── sqlservers.yml.example             # Variables template
│   ├── deploy_backups.yml                     # Main playbook
│   └── templates/
│       ├── 02_configure_database_mail.sql.j2  # Database Mail (templated)
│       ├── 03_backup_full.sql.j2              # Full backup (templated)
│       ├── 04_backup_log.sql.j2               # Log backup (templated)
│       └── backup.conf.j2                     # Config file (templated)
```

## How It Works

### Backup Flow

1. Cron triggers `run_backup.sh` with `FULL`, `LOG`, or `CHECKDB`
2. The script loads credentials from `/etc/sqlbackup/backup.conf`
3. It runs the appropriate SQL script via `sqlcmd`
4. Ola Hallengren's `DatabaseBackup` procedure:
   - Backs up each user database to `/mnt/sqlbackups/<DatabaseName>/`
   - Compresses using maximum compression settings
   - Encrypts using the TDE certificate (full backups)
   - Cleans up files older than retention period (only after successful backup)
   - Logs all activity to `dbo.CommandLog`
5. On failure: queries `CommandLog` for error details and emails helpdesk with server IP
6. On success (full only): checks that each database has at least 2 backups

### Retention Safety ("Never Delete Last 2")

- `@CleanupMode = 'AFTER_BACKUP'` ensures old files are only removed after a new backup succeeds
- `@CleanupTime = 168` (7 days) means only files older than 7 days are candidates
- Under normal daily operation, 7+ full backups exist per database
- If backups fail, cleanup never runs (requires success first)
- After each full backup, the script counts `.bak` files per database and alerts if any drop below 2

## Monitoring

### Log Files

- `/var/log/sqlbackup/cron_full.log` - Full backup cron output
- `/var/log/sqlbackup/cron_log.log` - Log backup cron output
- `/var/log/sqlbackup/cron_checkdb.log` - CHECKDB cron output
- `/var/log/sqlbackup/backup_FULL_<timestamp>.log` - Individual full backup run
- `/var/log/sqlbackup/backup_LOG_<timestamp>.log` - Individual log backup run
- `/var/log/sqlbackup/backup_CHECKDB_<timestamp>.log` - Individual CHECKDB run

### SQL Server CommandLog

```sql
-- Recent backup activity
SELECT TOP 20 * FROM master.dbo.CommandLog ORDER BY ID DESC;

-- Recent failures
SELECT * FROM master.dbo.CommandLog
WHERE ErrorNumber <> 0
ORDER BY ID DESC;
```

### Database Mail Queue

```sql
-- Check mail queue
SELECT * FROM msdb.dbo.sysmail_allitems ORDER BY send_request_date DESC;

-- Check for mail errors
SELECT * FROM msdb.dbo.sysmail_event_log ORDER BY log_date DESC;
```

## Troubleshooting

### "No TDE certificate found"

The full backup script auto-detects the TDE certificate. If detection fails:

1. Find the cert name manually (see Step 1 above)
2. Set `CERT_NAME="YourCertName"` in `/etc/sqlbackup/backup.conf`

### Backups not running

```bash
# Check cron is running
systemctl status cron

# Check cron entries
sudo crontab -l

# Run manually to see errors
sudo /opt/sqlbackup/run_backup.sh FULL
```

### Database Mail not sending

```sql
-- Check if Database Mail is enabled
SELECT name, value_in_use FROM sys.configurations WHERE name = 'Database Mail XPs';

-- Check mail log for errors
SELECT TOP 10 * FROM msdb.dbo.sysmail_event_log ORDER BY log_date DESC;

-- Resend a test
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'BackupAlerts',
    @recipients = 'alerts@example.com',
    @subject = 'Test',
    @body = 'Test email';
```

### Permission denied on /mnt/sqlbackups

```bash
sudo chown -R mssql:mssql /mnt/sqlbackups
sudo chmod 750 /mnt/sqlbackups
```
