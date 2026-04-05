# Progress Tracking

**Last Updated**: 2026-04-05

## Current State

The project is stable and functional. First real backup run completed successfully on db.rmserver.local.

## Completed Work

### Session: 2026-04-05 (second session)
- **Fixed CERT_NAME sqlcmd bug** — empty `CERT_NAME` in config caused `sqlcmd -v CERT_NAME=""` to reject the argument. Fixed by using `AUTO` as sentinel value; SQL script auto-detects TDE or skips encryption.
- **Made TDE encryption optional** — `03_backup_full.sql` no longer errors when no TDE certificate exists; backs up without encryption instead.
- **Added rsync to installer prerequisites** — `install.sh` now checks for rsync and installs it if missing.
- **Migrated all 12 user databases** from old server (192.168.100.79) to new server (192.168.100.77) — transferred data/log files via rsync, attached all databases, created GRManager login (db_owner on all user DBs).
- FULL and LOG backups confirmed working with all databases on new server.

### Session: 2026-04-05
- Analysed full project structure and codebase
- Created `CLAUDE.md` (project rules and guidelines)
- Created `.claude/Onboarding.md` (session startup instructions)
- Created `.claude/Progress.md` (this file)
- Configured `settings.local.json` with hook to auto-trigger onboarding

### Previous Development (from git history)
1. **Initial commit** (Mar 28) - SQL backup automation scripts and Ansible playbook
2. **Interactive installer** (Mar 29) - `install.sh` with guided setup, log backup recovery model filtering
3. **Bug fixes** (Mar 29) - TDE certificate detection, backup directory structure (`{BackupType}`), install summary UI
4. **Local-first backups** (Apr 4) - Backup to local XFS `/sqlbackup` then rsync to remote share; removed ~470 embedded lines from install.sh (now downloads from GitHub); pre-create per-database directories

## Known Issues / Open Items
- None currently identified

## What's Working
- Full backup with optional TDE encryption (auto-detect or skip)
- Transaction log backups (FULL recovery model only)
- DBCC CHECKDB integrity checks
- Database Mail failure notifications
- Local disk backup + rsync to network share
- Interactive installer (downloads scripts from GitHub, installs rsync)
- Ansible multi-server deployment
- Cron scheduling with configurable times

## Next Steps / Ideas
- Investigate database list query warning
- (Awaiting user direction)
