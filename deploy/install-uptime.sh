#!/usr/bin/env bash
# Sets up the down alerts (deploy/uptime-check.sh every 5 minutes) on the VM and on this PC.
# Messages go to the executive scheduler's alert LINE OA: its token is copied from that system's
# uptime.env (C:\exec-scheduler-uptime on this PC, /opt/exec-scheduler on the VM) and never shown.
#
#   bash deploy/install-uptime.sh            # install or update both, then check once
#   bash deploy/install-uptime.sh --test     # same, and send a test message from each
#   bash deploy/install-uptime.sh --remove   # take both off again
#
# VM:  /opt/imjang/deploy/uptime.env (kept by deploy-vm.sh), cron /etc/cron.d/imjang-uptime,
#      log /var/log/imjang-uptime.log
# PC:  C:\Imjang-uptime (uptime-check.sh copy, uptime.env, run-hidden.vbs, uptime.log),
#      Task Scheduler task "Imjang uptime" (while someone is signed in, no window)
# Run it again after changing deploy/uptime-check.sh or the list of sites below.
set -euo pipefail

CHECKS='อิ่มจัง|https://imjang.cpxsim.online/health'
VM_HOST="${VM_HOST:-cpxsim}"
APP_DIR=/opt/imjang
VM_SRC_ENV=/opt/exec-scheduler/uptime.env
DIR=/c/Imjang-uptime
WINDIR='C:\Imjang-uptime'
PC_SRC_ENV=/c/exec-scheduler-uptime/uptime.env
TASK='Imjang uptime'
BASH_EXE='C:\Program Files\Git\bin\bash.exe'
PS=/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
MODE="${1:-}"

SSH=ssh
[ -x /c/Windows/System32/OpenSSH/ssh.exe ] && SSH=/c/Windows/System32/OpenSSH/ssh.exe
vm() { "$SSH" -o BatchMode=yes -o ConnectTimeout=10 "$VM_HOST" "$@"; }
cd "$(dirname "$0")/.."

if [ "$MODE" = --remove ]; then
  vm "sudo rm -f /etc/cron.d/imjang-uptime" && echo "VM: cron removed (settings kept in $APP_DIR/deploy/uptime.env)"
  "$PS" -NoProfile -Command "Unregister-ScheduledTask -TaskName '$TASK' -Confirm:\$false -ErrorAction SilentlyContinue" || true
  echo "PC: task \"$TASK\" removed (settings and log kept in $WINDIR)"
  exit 0
fi

# Writes an uptime.env to stdout: the token line comes from the first file that has one.
make_env() { # source state_dir token_file...
  local src="$1" state="$2" f tok=''; shift 2
  for f in "$@"; do
    tok=$(grep -m1 '^LINE_ALERT_TOKEN=.' "$f" 2>/dev/null || true)
    [ -n "$tok" ] && break
  done
  printf '%s\n' \
    '# Down alerts for อิ่มจัง (deploy/uptime-check.sh every 5 minutes; written by deploy/install-uptime.sh).' \
    '# The token is the executive scheduler alert LINE OA one. Secret: never commit or show it.' \
    "${tok:-LINE_ALERT_TOKEN=}" \
    "SOURCE=\"$src\"" \
    "CHECKS=\"$CHECKS\"" \
    "STATE_DIR=\"$state\""
}

echo "== VM ($VM_HOST)"
vm "cat > $APP_DIR/deploy/uptime-check.sh && chmod +x $APP_DIR/deploy/uptime-check.sh" < deploy/uptime-check.sh
# The env file is built on the VM, so the token never leaves it. The script goes in on stdin:
# Thai text in a Windows command-line argument gets mangled.
vm 'bash -s' <<EOF
set -e
f=$APP_DIR/deploy/uptime.env
tok=\$(sudo grep -m1 '^LINE_ALERT_TOKEN=.' \$f $VM_SRC_ENV 2>/dev/null | head -1 | cut -d: -f2- || true)
umask 077
{ echo '# Down alerts for อิ่มจัง (deploy/uptime-check.sh every 5 minutes; written by deploy/install-uptime.sh).'
  echo '# The token is the executive scheduler alert LINE OA one. Secret: never commit or show it.'
  echo "\${tok:-LINE_ALERT_TOKEN=}"
  echo 'SOURCE="VM"'
  echo 'CHECKS="$CHECKS"'
  echo 'STATE_DIR="/var/lib/imjang-uptime"'; } > \$f.new
mv \$f.new \$f
echo '*/5 * * * * root /bin/bash $APP_DIR/deploy/uptime-check.sh $APP_DIR/deploy/uptime.env >> /var/log/imjang-uptime.log 2>&1' | sudo tee /etc/cron.d/imjang-uptime >/dev/null
sudo chmod 644 /etc/cron.d/imjang-uptime
echo '   cron: every 5 minutes'
grep -q '^LINE_ALERT_TOKEN=.' \$f && echo '   LINE token set' || echo '   NO LINE token (not found in $VM_SRC_ENV)'
EOF
vm "sudo bash $APP_DIR/deploy/uptime-check.sh $APP_DIR/deploy/uptime.env $MODE" | sed 's/^/   /'

echo "== PC ($WINDIR)"
mkdir -p "$DIR/state"
cp deploy/uptime-check.sh "$DIR/uptime-check.sh"
( umask 077; make_env "คอมสำนักงาน" "/c/Imjang-uptime/state" "$DIR/uptime.env" "$PC_SRC_ENV" > "$DIR/uptime.env.new" )
mv "$DIR/uptime.env.new" "$DIR/uptime.env"
printf '%s\r\n' \
  "' Runs อิ่มจัง's down-alert check with no window (made by deploy/install-uptime.sh)." \
  "CreateObject(\"WScript.Shell\").Run \"\"\"$BASH_EXE\"\" -c \"\"/c/Imjang-uptime/uptime-check.sh /c/Imjang-uptime/uptime.env >> /c/Imjang-uptime/uptime.log 2>&1\"\"\", 0, False" \
  > "$DIR/run-hidden.vbs"
"$PS" -NoProfile -Command "
\$a = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument '\"$WINDIR\\run-hidden.vbs\"'
\$t = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
\$s = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
Register-ScheduledTask -TaskName '$TASK' -Action \$a -Trigger \$t -Settings \$s -Description 'Imjang: LINE alert when imjang.cpxsim.online is down (deploy/install-uptime.sh)' -Force | Out-Null
'   Task Scheduler: $TASK, every ' + (Get-ScheduledTask -TaskName '$TASK').Triggers[0].Repetition.Interval
"
grep -q '^LINE_ALERT_TOKEN=.' "$DIR/uptime.env" && echo '   LINE token set' || echo "   NO LINE token (not found in $PC_SRC_ENV)"
bash "$DIR/uptime-check.sh" "$DIR/uptime.env" $MODE | sed 's/^/   /'
echo "== Done. Logs: VM /var/log/imjang-uptime.log, PC $WINDIR\\uptime.log"
