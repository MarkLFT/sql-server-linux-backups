-- =============================================================================
-- 03_backup_full.sql
-- Full backup of all user databases using Ola Hallengren's DatabaseBackup
-- =============================================================================
-- Called by run_backup.sh - do not run directly.
-- The TDE certificate name is injected via sqlcmd variable :CERT_NAME
-- =============================================================================

USE [master];
GO

DECLARE @cert_name NVARCHAR(128);
DECLARE @use_encryption CHAR(1) = 'N';

-- CERT_NAME is always passed from run_backup.sh (set to AUTO when not configured)
SET @cert_name = N'$(CERT_NAME)';

IF @cert_name <> N'AUTO'
BEGIN
    -- Explicit certificate name provided
    SET @use_encryption = 'Y';
END
ELSE
BEGIN
    -- Auto-detect the TDE certificate
    SET @cert_name = NULL;
    SELECT TOP 1 @cert_name = c.name
    FROM sys.dm_database_encryption_keys dek
    JOIN sys.certificates c ON dek.encryptor_thumbprint = c.thumbprint
    WHERE dek.database_id > 4;

    IF @cert_name IS NOT NULL
        SET @use_encryption = 'Y';
    ELSE
        PRINT 'No TDE certificate found - backups will not be encrypted';
END

IF @use_encryption = 'Y'
BEGIN
    PRINT 'Using TDE certificate: ' + @cert_name;

    EXEC dbo.DatabaseBackup
        @Databases          = 'USER_DATABASES',
        @Directory          = '$(BACKUP_DIR)',
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
END
ELSE
BEGIN
    EXEC dbo.DatabaseBackup
        @Databases          = 'USER_DATABASES',
        @Directory          = '$(BACKUP_DIR)',
        @BackupType         = 'FULL',
        @Compress           = 'Y',
        @MaxTransferSize    = 4194304,
        @CleanupTime        = 168,
        @CleanupMode        = 'AFTER_BACKUP',
        @LogToTable         = 'Y',
        @DirectoryStructure = '{DatabaseName}/{BackupType}',
        @FileName           = '{DatabaseName}_FULL_{Year}{Month}{Day}_{Hour}{Minute}{Second}.{FileExtension}';
END
GO
