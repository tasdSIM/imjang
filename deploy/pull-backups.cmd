@echo off
rem Run by the Windows scheduled task "Imjang backup pull" (every day 09:10): copies the VM's backups
rem to C:\Imjang-backups\vm (and OneDrive) with deploy\pull-backups.sh, logging to pull.log beside them.
rem It runs from wherever this checkout is. Set the task up again with deploy\install-backup-pull.ps1.
if not exist C:\Imjang-backups mkdir C:\Imjang-backups
cd /d "%~dp0.."
set CHERE_INVOKING=1
"C:\Program Files\Git\bin\bash.exe" -lc "bash deploy/pull-backups.sh" >> C:\Imjang-backups\pull.log 2>&1
