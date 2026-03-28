-- =============================================================================
-- 05_verify_setup.sql
-- Validates that all backup components are installed and configured
-- =============================================================================
-- Run with:
--   sqlcmd -S localhost -U SA -P '<YourPassword>' -i 05_verify_setup.sql
-- =============================================================================

USE [master];
GO

PRINT '==========================================================';
PRINT '  SQL Server Backup Setup - Verification Report';
PRINT '==========================================================';
PRINT '';

-- 1. Ola Hallengren stored procedures
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

-- 2. Database Mail
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

-- 3. User databases and recovery models
PRINT '--- User Databases ---';
SELECT
    name AS [Database],
    recovery_model_desc AS [Recovery Model],
    state_desc AS [State],
    CASE WHEN is_encrypted = 1 THEN 'Yes' ELSE 'No' END AS [TDE Encrypted]
FROM sys.databases
WHERE database_id > 4
ORDER BY name;

PRINT '';

-- 4. TDE certificate
PRINT '--- TDE Certificate ---';
IF EXISTS (
    SELECT 1 FROM sys.dm_database_encryption_keys dek
    JOIN sys.certificates c ON dek.encryptor_thumbprint = c.thumbprint
    WHERE dek.database_id > 4
)
BEGIN
    SELECT
        c.name AS [Certificate Name],
        c.expiry_date AS [Expiry Date],
        d.name AS [Used By Database]
    FROM sys.dm_database_encryption_keys dek
    JOIN sys.certificates c ON dek.encryptor_thumbprint = c.thumbprint
    JOIN sys.databases d ON dek.database_id = d.database_id
    WHERE dek.database_id > 4;
END
ELSE
    PRINT '[WARN] No TDE certificates found - backup encryption will fail';

PRINT '';

-- 5. Backup directory
PRINT '--- Backup Directory ---';
PRINT 'Verify /mnt/sqlbackups exists and is writable by the mssql user:';
PRINT '  sudo -u mssql test -w /mnt/sqlbackups && echo OK || echo FAIL';
PRINT '';

-- 6. Recent CommandLog entries
PRINT '--- Recent CommandLog Entries (last 10) ---';
IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL
BEGIN
    SELECT TOP 10
        ID,
        DatabaseName,
        CommandType,
        CASE WHEN ErrorNumber = 0 THEN 'Success' ELSE 'FAILED: ' + ISNULL(ErrorMessage, '') END AS Result,
        StartTime,
        EndTime
    FROM dbo.CommandLog
    ORDER BY ID DESC;
END
ELSE
    PRINT 'CommandLog table not found.';

PRINT '';

-- 7. Recent backup history
PRINT '--- Recent Backup History (last 10) ---';
SELECT TOP 10
    bs.database_name AS [Database],
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'L' THEN 'Log'
        WHEN 'I' THEN 'Diff'
    END AS [Type],
    bs.backup_finish_date AS [Completed],
    CAST(bs.compressed_backup_size / 1048576.0 AS DECIMAL(10,2)) AS [Size (MB)],
    CASE WHEN bs.is_encrypted = 1 THEN 'Yes' ELSE 'No' END AS [Encrypted],
    bmf.physical_device_name AS [File]
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
ORDER BY bs.backup_finish_date DESC;

PRINT '';
PRINT '==========================================================';
PRINT '  Verification complete';
PRINT '==========================================================';
GO
