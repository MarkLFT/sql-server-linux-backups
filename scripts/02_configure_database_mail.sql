-- =============================================================================
-- 02_configure_database_mail.sql
-- Configures Database Mail for backup failure notifications
-- =============================================================================
-- BEFORE RUNNING: Update the placeholder values below:
--   @smtp_server   = Your SMTP server hostname
--   @smtp_port     = SMTP port (587 for TLS, 465 for SSL, 25 for unencrypted)
--   @smtp_user     = SMTP authentication username
--   @smtp_password = SMTP authentication password
--   @sender_email  = From address for notification emails
--   @enable_ssl    = 1 for TLS/SSL, 0 for unencrypted
--
-- Run with:
--   sqlcmd -S localhost -U SA -P '<YourPassword>' -i 02_configure_database_mail.sql
-- =============================================================================

USE [msdb];
GO

-- ---- Configuration Variables ------------------------------------------------
DECLARE @smtp_server   NVARCHAR(128) = N'smtp.example.com';       -- CHANGE THIS
DECLARE @smtp_port     INT           = 587;                        -- CHANGE THIS
DECLARE @smtp_user     NVARCHAR(128) = N'alerts@example.com';     -- CHANGE THIS
DECLARE @smtp_password NVARCHAR(128) = N'<change_me>';            -- CHANGE THIS
DECLARE @sender_email  NVARCHAR(128) = N'sqlbackups@example.com'; -- CHANGE THIS
DECLARE @enable_ssl    BIT           = 1;                          -- 1=TLS, 0=none

DECLARE @recipient     NVARCHAR(128) = N'alerts@example.com';
DECLARE @profile_name  NVARCHAR(128) = N'BackupAlerts';
DECLARE @account_name  NVARCHAR(128) = N'BackupSMTP';

-- ---- Enable Database Mail XPs -----------------------------------------------
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Database Mail XPs', 1;
RECONFIGURE;

PRINT '[OK] Database Mail XPs enabled';

-- ---- Drop existing profile/account if re-running ----------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profileaccount pa
           JOIN msdb.dbo.sysmail_profile p ON pa.profile_id = p.profile_id
           JOIN msdb.dbo.sysmail_account a ON pa.account_id = a.account_id
           WHERE p.name = @profile_name AND a.name = @account_name)
BEGIN
    EXEC msdb.dbo.sysmail_delete_profileaccount_sp
        @profile_name = @profile_name,
        @account_name = @account_name;
END

IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile WHERE name = @profile_name)
    EXEC msdb.dbo.sysmail_delete_profile_sp @profile_name = @profile_name;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysmail_account WHERE name = @account_name)
    EXEC msdb.dbo.sysmail_delete_account_sp @account_name = @account_name;

-- ---- Create Mail Account ----------------------------------------------------
EXEC msdb.dbo.sysmail_add_account_sp
    @account_name   = @account_name,
    @description    = N'SMTP account for SQL Server backup alerts',
    @email_address  = @sender_email,
    @display_name   = N'SQL Backup Alerts',
    @mailserver_name = @smtp_server,
    @port           = @smtp_port,
    @username       = @smtp_user,
    @password       = @smtp_password,
    @enable_ssl     = @enable_ssl;

PRINT '[OK] Mail account created';

-- ---- Create Mail Profile ----------------------------------------------------
EXEC msdb.dbo.sysmail_add_profile_sp
    @profile_name = @profile_name,
    @description  = N'Profile for sending backup failure notifications';

PRINT '[OK] Mail profile created';

-- ---- Link Account to Profile ------------------------------------------------
EXEC msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name    = @profile_name,
    @account_name    = @account_name,
    @sequence_number = 1;

-- ---- Grant access to the profile (public role) ------------------------------
EXEC msdb.dbo.sysmail_add_principalsecurity_sp
    @profile_name    = @profile_name,
    @principal_name  = N'public',
    @is_default      = 1;

PRINT '[OK] Mail profile linked to account and set as default';

-- ---- Send Test Email --------------------------------------------------------
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = @profile_name,
    @recipients   = @recipient,
    @subject      = N'SQL Server Backup Alerts - Test Email',
    @body         = N'This is a test email from SQL Server Database Mail. If you received this, backup notifications are configured correctly.',
    @body_format  = N'TEXT';

PRINT '[OK] Test email sent to ' + @recipient;
PRINT '     Check the inbox and verify delivery.';
PRINT '';
PRINT '     If not received, check the mail queue:';
PRINT '       SELECT * FROM msdb.dbo.sysmail_allitems ORDER BY send_request_date DESC;';
PRINT '       SELECT * FROM msdb.dbo.sysmail_event_log ORDER BY log_date DESC;';
GO
