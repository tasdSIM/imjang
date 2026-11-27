#!/usr/bin/env bash
# Account admin on the VM (runs server/admin.js inside the app's container).
#
#   bash deploy/admin.sh                    # list accounts with their ids
#   bash deploy/admin.sh u_xxxxxx           # temporary password for someone who forgot theirs
#
# There is no e-mail, so make sure it is really their account first (for example the pet's name
# and roughly when they signed up), then tell them the temporary password privately.
set -euo pipefail
VM_HOST="${VM_HOST:-cpxsim}"
SSH=ssh
[ -x /c/Windows/System32/OpenSSH/ssh.exe ] && SSH=/c/Windows/System32/OpenSSH/ssh.exe
run="cd /opt/imjang && sudo docker compose -p imjang exec -T web node server/admin.js"
if [ $# -eq 0 ]; then
  "$SSH" -o BatchMode=yes "$VM_HOST" "$run list"
else
  [[ "$1" =~ ^u_[A-Za-z0-9_-]{6,30}$ ]] || { echo "Give the account id (u_...), from: bash deploy/admin.sh" >&2; exit 2; }
  "$SSH" -o BatchMode=yes "$VM_HOST" "$run reset-password $1"
fi
