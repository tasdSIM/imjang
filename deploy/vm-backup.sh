#!/usr/bin/env bash
# Backs up the accounts and saves on the VM: one small file, /opt/imjang-backups/imjang-<kind>-<date>.db.gz,
# made by SQLite itself (VACUUM INTO), so the copy is whole even while people are using the app.
#
#   vm-backup.sh daily    # every night at 02:50 Thai time from cron (/etc/cron.d/imjang-backup); keeps 30
#   vm-backup.sh deploy   # before every deploy (deploy-vm.sh); keeps 14
#
# The privacy policy (privacy.html) promises backups are kept at most 30 days: keep KEEP in step with it.
#
# To restore one: stop the app, put the unzipped file in the data volume as imjang.db
# (removing imjang.db-wal and -shm), and start it again:
#   cd /opt/imjang && sudo docker compose -p imjang stop
#   sudo sh -c 'gunzip -c /opt/imjang-backups/imjang-daily-<date>.db.gz > /tmp/restore.db'
#   sudo docker run --rm -v imjang_data:/data -v /tmp:/in alpine sh -c \
#     'rm -f /data/imjang.db-wal /data/imjang.db-shm && cp /in/restore.db /data/imjang.db && chown 1000:1000 /data /data/imjang.db'
#   sudo docker compose -p imjang start
set -euo pipefail

KIND="${1:-daily}"
case "$KIND" in
  daily) KEEP=30 ;;
  deploy) KEEP=14 ;;
  *) echo "usage: $0 daily|deploy" >&2; exit 2 ;;
esac
DIR=/opt/imjang-backups
CONTAINER=imjang-web-1
OUT="$DIR/imjang-$KIND-$(date +%Y%m%d-%H%M%S).db.gz"

sudo mkdir -p "$DIR"
sudo chmod 700 "$DIR"
if sudo docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  sudo docker exec "$CONTAINER" node -e "
    const { DatabaseSync } = require('node:sqlite');
    require('node:fs').rmSync('/data/snapshot.db', { force: true });
    new DatabaseSync('/data/imjang.db').exec(\"VACUUM INTO '/data/snapshot.db'\");
  " 2>/dev/null
  sudo docker exec "$CONTAINER" cat /data/snapshot.db | gzip | sudo tee "$OUT" >/dev/null
  sudo docker exec "$CONTAINER" rm -f /data/snapshot.db
elif sudo docker volume inspect imjang_data >/dev/null 2>&1; then
  # The app is not running: copy the database file straight from the volume.
  sudo docker run --rm -v imjang_data:/data alpine sh -c 'cat /data/imjang.db 2>/dev/null' | gzip | sudo tee "$OUT" >/dev/null
else
  echo "$(date '+%F %T') nothing to back up yet (first install)"
  exit 0
fi
if ! sudo test -s "$OUT"; then sudo rm -f "$OUT"; echo "$(date '+%F %T') backup is empty (no database yet)"; exit 0; fi
echo "$(date '+%F %T') backup $OUT $(sudo du -h "$OUT" | cut -f1)"
sudo sh -c "ls -1t $DIR/imjang-$KIND-*.db.gz | tail -n +$((KEEP + 1)) | xargs -r rm -f"
# and nothing older than 30 days, deploy copies included (privacy.html)
sudo find "$DIR" -maxdepth 1 -name 'imjang-*.db.gz' -mtime +30 -delete
