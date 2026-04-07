-- =============================================================================
-- 08_backup_system.sql
-- Full backup of system databases using Ola Hallengren's DatabaseBackup
-- =============================================================================
-- Called by run_backup.sh SYSTEM - do not run directly.
-- Backs up master, msdb, and model (system databases).
-- =============================================================================

USE [master];
GO

EXEC dbo.DatabaseBackup
    @Databases = 'SYSTEM_DATABASES',
    @Directory = '$(BACKUP_DIR)',
    @BackupType = 'FULL',
    @Compress = 'Y',
    @MaxTransferSize = 4194304,
    @CleanupTime = 168,
    @CleanupMode = 'AFTER_BACKUP',
    @LogToTable = 'Y',
    @DirectoryStructure = '{DatabaseName}/{BackupType}',
    @FileName = '{DatabaseName}_FULL_{Year}{Month}{Day}_{Hour}{Minute}{Second}.{FileExtension}';
GO
