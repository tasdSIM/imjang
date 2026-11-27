#!/usr/bin/env bash
# Copies the VM's backups to this computer, so they survive if the VM is lost, and on into OneDrive,
# so they also survive if this computer is lost. Same as the detective game's.
#
#   bash deploy/pull-backups.sh                 # into C:\Imjang-backups\vm
#   BACKUP_DIR=/d/backups bash deploy/pull-backups.sh
#   CLOUD_DIR=none bash deploy/pull-backups.sh  # skip the OneDrive copy
#
# Only files not there yet are copied. The files hold people's health data (weight, food) and
# account names with password hashes: keep both folders private and never share them.
# The privacy policy promises backups are kept at most 30 days, so copies older than that are
# removed here too (PRUNE_DAYS).
set -euo pipefail

VM_HOST="${VM_HOST:-cpxsim}"
BACKUP_DIR="${BACKUP_DIR:-/c/Imjang-backups/vm}"
PRUNE_DAYS="${PRUNE_DAYS:-31}"
if [ -z "${CLOUD_DIR:-}" ] && [ -n "${OneDrive:-}" ]; then
  CLOUD_DIR="$(cygpath -u "$OneDrive" 2>/dev/null || echo "$OneDrive")/Imjang-backups/vm"
fi
REMOTE=/opt/imjang-backups
SSH=ssh
[ -x /c/Windows/System32/OpenSSH/ssh.exe ] && SSH=/c/Windows/System32/OpenSSH/ssh.exe
vm() { "$SSH" -o BatchMode=yes -o ConnectTimeout=10 "$VM_HOST" "$@"; }

mkdir -p "$BACKUP_DIR"
pulled=0
reached=no
if vm true </dev/null; then
  reached=yes
  mapfile -t remote < <(vm "sudo sh -c 'cd $REMOTE && ls -1 imjang-*'" </dev/null)
  new=()
  for f in "${remote[@]}"; do [ -s "$BACKUP_DIR/$f" ] || new+=("$f"); done
  if [ ${#new[@]} -gt 0 ]; then
    vm "sudo tar -C $REMOTE -cf - ${new[*]}" </dev/null | tar -xf - -C "$BACKUP_DIR"
    for f in "${new[@]}"; do
      case "$f" in *.gz) gzip -t "$BACKUP_DIR/$f" || { echo "   broken: $f" >&2; rm -f "$BACKUP_DIR/$f"; }; esac
    done
  fi
  pulled=${#new[@]}
else
  echo "$(date '+%F %T') cannot reach $VM_HOST (is the key loaded? ssh-add ~/.ssh/id_ed25519)" >&2
fi

clouded=0
if [ -n "${CLOUD_DIR:-}" ] && [ "$CLOUD_DIR" != none ]; then
  mkdir -p "$CLOUD_DIR"
  for p in "$BACKUP_DIR"/imjang-*; do
    [ -e "$p" ] || continue
    f=$(basename "$p")
    [ -s "$CLOUD_DIR/$f" ] && continue
    cp "$p" "$CLOUD_DIR/$f.part" && mv "$CLOUD_DIR/$f.part" "$CLOUD_DIR/$f" && clouded=$((clouded + 1))
  done
fi

# Deleted accounts must not live on in old copies.
for d in "$BACKUP_DIR" ${CLOUD_DIR:+"$CLOUD_DIR"}; do
  [ -d "$d" ] && find "$d" -maxdepth 1 -name 'imjang-*.db.gz' -mtime +"$PRUNE_DAYS" -delete || true
done

echo "$(date '+%F %T') pulled $pulled new; $(ls -1 "$BACKUP_DIR" | grep -c '^imjang-') backups in $BACKUP_DIR${CLOUD_DIR:+; $clouded new to OneDrive}"
[ $reached = yes ] || exit 1
