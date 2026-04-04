-- =============================================================================
-- 04_backup_log.sql
-- Transaction log backup of user databases in FULL recovery model
-- =============================================================================
-- Called by run_backup.sh - do not run directly.
-- Only databases in FULL recovery model can have transaction log backups.
-- Databases in SIMPLE recovery model are skipped automatically.
-- =============================================================================

USE [master];
GO

-- Build a comma-separated list of user databases in FULL recovery model
DECLARE @db_list NVARCHAR(MAX) = N'';

SELECT @db_list = @db_list + QUOTENAME(name) + N','
FROM sys.databases
WHERE database_id > 4
  AND state = 0             -- ONLINE
  AND recovery_model = 1;   -- FULL

-- Trim trailing comma
SET @db_list = LEFT(@db_list, LEN(@db_list) - 1);

IF @db_list = N''
BEGIN
    PRINT 'No user databases in FULL recovery model - skipping log backup.';
    RETURN;
END

PRINT 'Log backup targets: ' + @db_list;

EXEC dbo.DatabaseBackup
    @Databases          = @db_list,
    @Directory          = '$(BACKUP_DIR)',
    @BackupType         = 'LOG',
    @Compress           = 'Y',
    @MaxTransferSize    = 4194304,
    @CleanupTime        = 48,
    @CleanupMode        = 'AFTER_BACKUP',
    @LogToTable         = 'Y',
    @DirectoryStructure = '{DatabaseName}/{BackupType}',
    @FileName           = '{DatabaseName}_LOG_{Year}{Month}{Day}_{Hour}{Minute}{Second}.{FileExtension}';
GO
