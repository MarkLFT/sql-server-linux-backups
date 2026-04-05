# Onboarding - Read and Action Every New Session

**ACTION THIS FILE AT THE START OF EVERY SESSION.**

## Steps to Execute

### 1. Understand the Project
This is a **SQL Server Backup Solution** for SQL Server 2022 on Linux. It uses Ola Hallengren's Maintenance Solution with bash wrapper scripts, cron scheduling, and Ansible for multi-server deployment. Read `CLAUDE.md` in the project root for full rules and structure.

### 2. Check Current Progress
Read `.claude/Progress.md` to understand:
- What was being worked on in the last session
- Any incomplete tasks or known issues
- Current state of the project

### 3. Check Recent Git Activity
Run these commands to understand recent changes:
```bash
git log --oneline -10
git status
git diff --stat HEAD~1
```
This tells you what was last committed and if there are any uncommitted changes.

### 4. Check for Uncommitted Work
Run `git status` to see if there are staged/unstaged changes from a previous session that may need attention.

### 5. Brief the User
After completing steps 1-4, provide a brief summary to the user:
- What the project is (1 sentence)
- What was last worked on (from Progress.md and git log)
- Current state (clean/dirty working tree, any pending work)
- Ask what they'd like to work on today

## Ongoing: Keep Progress.md Updated
Throughout the session, you MUST update `.claude/Progress.md` after every significant task. This is the handoff document for the next session. Update it with what was done, what's in progress, any blockers, and next steps. Do not wait until the end - update as you go.

## Key Files to Know

| File | Purpose |
|------|---------|
| `install.sh` | Interactive installer (main entry point for setup) |
| `scripts/run_backup.sh` | Backup wrapper called by cron |
| `scripts/03_backup_full.sql` | Full backup T-SQL |
| `scripts/04_backup_log.sql` | Log backup T-SQL |
| `scripts/06_checkdb.sql` | DBCC CHECKDB |
| `ansible/deploy_backups.yml` | Multi-server Ansible playbook |
| `README.md` | User-facing documentation |
| `CLAUDE.md` | Claude rules and project guidelines |
| `.claude/Progress.md` | Session progress tracking |
