-- =============================================================================
-- 01_install_ola_hallengren.sql
-- Installs Ola Hallengren's SQL Server Maintenance Solution
-- =============================================================================
-- PREREQUISITES:
--   Download MaintenanceSolution.sql from:
--   https://github.com/olahallengren/sql-server-maintenance-solution/releases
--
--   Place it in the same directory as this script, then run:
--     sqlcmd -S localhost -U SA -P '<YourPassword>' -i MaintenanceSolution.sql
--
-- This script verifies the installation was successful.
-- =============================================================================

USE [master];
GO

-- Verify core objects exist after running MaintenanceSolution.sql
PRINT '=== Verifying Ola Hallengren Installation ===';
PRINT '';

-- Check stored procedures
IF OBJECT_ID('dbo.DatabaseBackup', 'P') IS NOT NULL
    PRINT '[OK] dbo.DatabaseBackup exists';
ELSE
    PRINT '[FAIL] dbo.DatabaseBackup NOT FOUND - run MaintenanceSolution.sql first';

IF OBJECT_ID('dbo.DatabaseIntegrityCheck', 'P') IS NOT NULL
    PRINT '[OK] dbo.DatabaseIntegrityCheck exists';
ELSE
    PRINT '[FAIL] dbo.DatabaseIntegrityCheck NOT FOUND';

IF OBJECT_ID('dbo.IndexOptimize', 'P') IS NOT NULL
    PRINT '[OK] dbo.IndexOptimize exists';
ELSE
    PRINT '[FAIL] dbo.IndexOptimize NOT FOUND';

-- Check CommandLog table
IF OBJECT_ID('dbo.CommandLog', 'U') IS NOT NULL
    PRINT '[OK] dbo.CommandLog table exists';
ELSE
    PRINT '[FAIL] dbo.CommandLog table NOT FOUND';

PRINT '';
PRINT '=== Installation verification complete ===';
GO
