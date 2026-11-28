# Sets up (or updates) the Windows scheduled task "Imjang backup pull": every day at 09:10 it runs
# deploy\pull-backups.cmd, which copies the VM's database backups to C:\Imjang-backups\vm and OneDrive.
# Same as the detective game's "Murdle Logic backup pull" (09:05). Runs while you are signed in; a
# missed run (PC off at 09:10) starts when the PC is next on.
#   powershell -ExecutionPolicy Bypass -File deploy\install-backup-pull.ps1
#   powershell -ExecutionPolicy Bypass -File deploy\install-backup-pull.ps1 -Remove
param([switch]$Remove)
$name = 'Imjang backup pull'
if ($Remove) { Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue; "removed: $name"; return }
$cmd = Join-Path $PSScriptRoot 'pull-backups.cmd'
$a = New-ScheduledTaskAction -Execute $cmd
$t = New-ScheduledTaskTrigger -Daily -At '09:10'
$s = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName $name -Action $a -Trigger $t -Settings $s -Description 'Imjang: copy the VM database backups to this PC and OneDrive (deploy\install-backup-pull.ps1)' -Force | Out-Null
$k = Get-ScheduledTask -TaskName $name
"task: $name -> $cmd, daily at " + ([datetime]$k.Triggers[0].StartBoundary).ToString('HH:mm')
