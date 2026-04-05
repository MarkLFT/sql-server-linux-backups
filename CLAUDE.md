# CLAUDE.md - Project Rules & Guidelines

## Project Overview

**SQL Server Backup Solution** - Automated backup automation for SQL Server 2022 on Linux using Ola Hallengren's Maintenance Solution. Provides scheduled full backups, transaction log backups, and DBCC CHECKDB with email notifications via Database Mail.

## Tech Stack

- **T-SQL** - SQL Server stored procedures & backup scripts
- **Bash** - Installation, wrapper scripts, cron orchestration
- **Ansible** - Infrastructure-as-code for multi-server deployment
- **Target Platform** - SQL Server 2022 on Linux

## Session Lifecycle

### Session Startup
**IMPORTANT**: At the start of every new session, read and action `.claude/Onboarding.md`.

### Session Progress Tracking
**CRITICAL**: You MUST keep `.claude/Progress.md` up to date throughout every session:
- Update it after completing any significant task or milestone
- Update it before responding to the user's final message if the conversation appears to be winding down
- Update it whenever you finish a multi-step piece of work
- Include: what was done, what's in progress, any blockers, and what remains
- This file is the handoff document for the next session - treat it as essential, not optional

## Project Structure

```
sqlbackups/
├── install.sh                     # Interactive single-server installer
├── README.md                      # Full documentation
├── scripts/
│   ├── 01_install_ola_hallengren.sql   # Ola Hallengren verification
│   ├── 02_configure_database_mail.sql  # Database Mail setup
│   ├── 03_backup_full.sql              # Full backup T-SQL
│   ├── 04_backup_log.sql              # Transaction log backup T-SQL
│   ├── 05_verify_setup.sql            # Post-deployment verification
│   ├── 06_checkdb.sql                 # DBCC CHECKDB
│   ├── run_backup.sh                  # Main backup wrapper (called by cron)
│   ├── setup_cron.sh                  # Cron job installer
│   └── backup.conf.example            # Config template
├── ansible/
│   ├── deploy_backups.yml             # Main Ansible playbook
│   ├── inventory.yml.example          # Server inventory template
│   ├── group_vars/
│   │   └── sqlservers.yml.example     # Variables template
│   └── templates/                     # Jinja2 templates for Ansible
└── .claude/
    ├── settings.local.json
    ├── Onboarding.md
    └── Progress.md
```

## Architecture & Workflow

```
Cron Trigger -> run_backup.sh [FULL|LOG|CHECKDB]
  -> Load /etc/sqlbackup/backup.conf
  -> Execute T-SQL via sqlcmd
  -> Ola Hallengren's DatabaseBackup procedure
     ├─ Backup to /sqlbackup (local XFS)
     ├─ Log to dbo.CommandLog
     └─ rsync to /mnt/sqlbackups (network share)
  -> On Failure: query CommandLog + send email via Database Mail
```

## Coding Rules

### General
- This is a Linux-targeted solution; all bash scripts must be POSIX-compatible where possible
- Use `set -euo pipefail` in all bash scripts
- SQL scripts use `sqlcmd` (mssql-tools18) for execution

### Bash Scripts
- Use double quotes around all variable expansions
- All paths should be configurable via `backup.conf`, not hardcoded
- Error handling: always check `sqlcmd` exit codes and `CommandLog` for failures
- Log output to `/var/log/sqlbackup/`

### T-SQL Scripts
- Use Ola Hallengren's stored procedures (`DatabaseBackup`, `DatabaseIntegrityCheck`) - do not write custom backup logic
- Always use `@Databases = 'USER_DATABASES'` unless there's a specific reason not to
- Backup parameters: `COMPRESSION`, `MAXTRANSFERSIZE = 4194304`
- TDE encryption: auto-detect certificates, use `AES_256`
- Retention: configurable but defaults are 7 days (full), 2 days (log)
- Log backups: filter to `FULL` recovery model databases only

### Ansible
- Sensitive values (passwords, SMTP credentials) go in Ansible Vault
- Templates use Jinja2 (`.j2` extension)
- Playbook targets the `sqlservers` group

### install.sh
- Downloads scripts from GitHub at install time (not embedded)
- Interactive prompts for all configuration
- Must pre-create per-database backup directories
- Auto-detects TDE certificates

## Deployment Methods

1. **Interactive Installer** (`install.sh`) - Single server, guided setup
2. **Manual** - Step-by-step using individual scripts
3. **Ansible** (`ansible/deploy_backups.yml`) - Multi-server automated rollout

## Default Schedule

| Task | Schedule | Retention |
|------|----------|-----------|
| Full Backup | Daily 05:00 | 7 days |
| Transaction Log | Hourly (skips 05:00) | 2 days |
| DBCC CHECKDB | Wednesday 03:00 | N/A |

## Key Dependencies

- SQL Server 2022 on Linux
- `sqlcmd` (mssql-tools18)
- Ola Hallengren's Maintenance Solution
- rsync (for local -> remote backup sync)
- SMTP server for email notifications
