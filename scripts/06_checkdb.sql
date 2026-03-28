-- =============================================================================
-- 06_checkdb.sql
-- DBCC CHECKDB on all user databases using Ola Hallengren's DatabaseIntegrityCheck
-- =============================================================================
-- Called by run_backup.sh CHECKDB - do not run directly.
-- Runs BEFORE the weekly full backup to detect corruption early.
-- =============================================================================

USE [master];
GO

EXEC dbo.DatabaseIntegrityCheck
    @Databases = 'USER_DATABASES',
    @LogToTable = 'Y';
GO
