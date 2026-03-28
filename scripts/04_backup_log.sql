-- =============================================================================
-- 04_backup_log.sql
-- Transaction log backup of all user databases using Ola Hallengren
-- =============================================================================
-- Called by run_backup.sh - do not run directly.
-- =============================================================================

USE [master];
GO

EXEC dbo.DatabaseBackup
    @Databases          = 'USER_DATABASES',
    @Directory          = '/mnt/sqlbackups',
    @BackupType         = 'LOG',
    @Compress           = 'Y',
    @MaxTransferSize    = 4194304,
    @CleanupTime        = 48,
    @CleanupMode        = 'AFTER_BACKUP',
    @LogToTable         = 'Y',
    @DirectoryStructure = '{DatabaseName}',
    @FileName           = '{DatabaseName}_LOG_{Year}{Month}{Day}_{Hour}{Minute}{Second}.{FileExtension}';
GO
