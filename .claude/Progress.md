# Progress Tracking

**Last Updated**: 2026-04-07

## Current State

Project is stable. New index optimize and system backup jobs added. Deployed to server, monitoring for results.

## Completed Work

### Session: 2026-04-07
- **Diagnosed missing backups** — Zabbix alerting databases >48h without backup. Root cause: Proxmox host being physically power-buttoned off daily ~07:00, causing VMs to miss the 05:00 backup window. April 5 & 6 backups failed; April 7 succeeded.
- **Identified power button issue** — `systemd-logind` logs show "Power key pressed short" on Proxmox host (SdlwdPVE2). Someone physically pressing power button after failed login attempts on tty1. Recommended `HandlePowerKey=ignore` in `/etc/systemd/logind.conf`.
- **Added weekly IndexOptimize** — New `07_index_optimize.sql` using Ola Hallengren's `IndexOptimize` for index rebuild/reorg and statistics updates. Scheduled Monday 01:00.
- **Added system database backups** — New `08_backup_system.sql` using `@Databases = 'SYSTEM_DATABASES'` for master/msdb/model. Scheduled daily 05:30.
- **Updated run_backup.sh** — Now supports `INDEXOPT` and `SYSTEM` backup types, with correct directory pre-creation for system databases.
- **Updated setup_cron.sh** — Includes all five job types in cron file and script verification.
- **Deployed** — Pushed to GitHub, provided curl commands for server deployment.

### Session: 2026-04-05 (second session)
- Fixed CERT_NAME sqlcmd bug — empty `CERT_NAME` caused sqlcmd to reject argument. Fixed with `AUTO` sentinel.
- Made TDE encryption optional — backs up without encryption if no TDE certificate.
- Added rsync to installer prerequisites.
- Migrated all 12 user databases from old server (192.168.100.79) to new server (192.168.100.77).
- FULL and LOG backups confirmed working.

### Session: 2026-04-05
- Created `CLAUDE.md`, `.claude/Onboarding.md`, `.claude/Progress.md`
- Configured session management

## Known Issues / Open Items
- **Proxmox power button** — User needs to apply `HandlePowerKey=ignore` on Proxmox host to prevent unauthorized shutdowns
- **Monitor new jobs** — Verify IndexOptimize runs successfully on Monday 01:00 and system backup runs at 05:30
- **Failure notifications** — When SQL Server is down, Database Mail can't send alerts. Local sendmail fallback not yet implemented.

## Current Schedule

| Task | Schedule | Databases |
|------|----------|-----------|
| Index optimize + stats | Monday 01:00 | User DBs |
| DBCC CHECKDB | Wednesday 03:00 | User DBs |
| Full backup | Daily 05:00 | User DBs |
| System backup | Daily 05:30 | master, msdb, model |
| Log backup | Hourly (except 05:00) | User DBs (FULL recovery only) |

## Next Steps / Ideas
- Add local sendmail fallback for failure notifications when SQL Server is unreachable
- Consider catch-up backup systemd service for post-reboot scenarios
- (Awaiting user direction)
