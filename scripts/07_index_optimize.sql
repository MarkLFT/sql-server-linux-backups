-- =============================================================================
-- 07_index_optimize.sql
-- Index rebuild/reorganize and statistics update using Ola Hallengren's IndexOptimize
-- =============================================================================
-- Called by run_backup.sh INDEXOPT - do not run directly.
-- Rebuilds fragmented indexes and updates statistics on all user databases.
-- =============================================================================

USE [master];
GO

EXEC dbo.IndexOptimize
    @Databases = 'USER_DATABASES',
    @FragmentationLow = NULL,
    @FragmentationMedium = 'INDEX_REORGANIZE',
    @FragmentationHigh = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
    @FragmentationLevel1 = 5,
    @FragmentationLevel2 = 30,
    @UpdateStatistics = 'ALL',
    @OnlyModifiedStatistics = 'Y',
    @LogToTable = 'Y';
GO
