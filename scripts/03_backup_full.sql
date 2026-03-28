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

-- Auto-detect the TDE certificate if not provided via sqlcmd variable
SET @cert_name = N'$(CERT_NAME)';

IF @cert_name = N'' OR @cert_name = N'$(CERT_NAME)'
BEGIN
    -- Find the certificate used for TDE on any database
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
    @DirectoryStructure = '{DatabaseName}',
    @FileName           = '{DatabaseName}_FULL_{Year}{Month}{Day}_{Hour}{Minute}{Second}.{FileExtension}';
GO
