#!/usr/bin/env bash
# Puts the committed app (HEAD) on the VM that serves https://imjang.cpxsim.online.
# Same steps as the detective game's deploy:
#
#   bash deploy/deploy-vm.sh
#
#   1. backs up the accounts and saves on the VM (deploy/vm-backup.sh; keeps the last 14),
#   2. copies HEAD to /opt/imjang,
#   3. builds and restarts the app there; the build runs test/server.js, so a failing build
#      leaves the old version running,
#   4. makes sure the nightly backup is scheduled (cron, 02:50 Thai time = 19:50 UTC, keeps 30),
#   5. checks /health on the VM and through the public address.
#
# Wholly apart from CPX prod, ARMY-INTEL, Coding Adventure, the detective game and ไฟรักไม่มอด:
# own folder (/opt/imjang), project (imjang), loopback port 8095 and its own Cloudflare tunnel
# (route imjang.cpxsim.online -> http://web:8080, set in the Cloudflare dashboard).
# Only committed code is sent, so commit first. Kept on the VM, never sent from git:
# deploy/tunnel.env (the tunnel token), deploy/uptime.env (down alerts, deploy/install-uptime.sh) and
# docker-compose.override.yml (runs cloudflared next to the app). A first install copies the local deploy/tunnel.env up and writes the override.
#
# VM_HOST is an ssh host alias (default "cpxsim", set in ~/.ssh/config). On Windows the
# key's passphrase sits in the Windows ssh-agent, which only Windows' own ssh.exe can use.
set -euo pipefail

VM_HOST="${VM_HOST:-cpxsim}"
APP_DIR=/opt/imjang
PROJECT=imjang
PORT=8095
PUBLIC_URL=https://imjang.cpxsim.online

SSH=ssh
[ -x /c/Windows/System32/OpenSSH/ssh.exe ] && SSH=/c/Windows/System32/OpenSSH/ssh.exe
vm() { "$SSH" -o BatchMode=yes -o ConnectTimeout=10 "$VM_HOST" "$@"; }

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
REV=$(git rev-parse --short HEAD)
echo "== Deploying $REV: $(git log -1 --format=%s)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "   Note: uncommitted changes are not sent; only $REV is."
fi
if [ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}' 2>/dev/null || true)" ]; then
  echo "   Note: $REV is not the same as the pushed branch on GitHub."
fi

echo "== Checking the VM"
vm true || {
  echo "Cannot reach $VM_HOST. If the key needs its passphrase, run: ssh-add ~/.ssh/id_ed25519" >&2
  exit 1
}
# First deploy only: the port must be free (other apps on this VM use 8093, 8094 …).
if ! vm "test -f $APP_DIR/REVISION" && vm "ss -ltn | grep -q '127.0.0.1:$PORT '"; then
  echo "Port $PORT is already used on the VM. Pick another in docker-compose.yml and this script." >&2
  exit 1
fi
vm "sudo mkdir -p $APP_DIR/deploy && sudo chown \$(id -u):\$(id -g) $APP_DIR $APP_DIR/deploy"
if ! vm "test -s $APP_DIR/deploy/tunnel.env"; then
  [ -s deploy/tunnel.env ] || { echo "No tunnel token: put TUNNEL_TOKEN=... in deploy/tunnel.env (never committed)." >&2; exit 1; }
  echo "   Installing the tunnel token on the VM"
  vm "umask 077 && cat > $APP_DIR/deploy/tunnel.env" < deploy/tunnel.env
fi
vm "test -f $APP_DIR/docker-compose.override.yml || cat > $APP_DIR/docker-compose.override.yml" <<'EOF'
# VM only (not in git). The app's own Cloudflare tunnel runs here next to it:
# its route imjang.cpxsim.online -> http://web:8080. The token is in deploy/tunnel.env (never committed).
services:
  cloudflared:
    image: cloudflare/cloudflared:2026.10.1
    restart: unless-stopped
    # http2 over TCP 443: the VM's network drops outbound UDP, so the default QUIC never connects.
    command: tunnel --no-autoupdate --protocol http2 run
    env_file: deploy/tunnel.env
    depends_on: [web]
EOF
echo "   Running now: $(vm "cat $APP_DIR/REVISION 2>/dev/null || echo 'nothing (first deploy)'")"

echo "== Backing up accounts and saves"
vm 'cat > /tmp/imjang-backup.sh && bash /tmp/imjang-backup.sh deploy; s=$?; rm -f /tmp/imjang-backup.sh; exit $s' < deploy/vm-backup.sh

echo "== Copying $REV"
vm "find $APP_DIR -mindepth 1 -maxdepth 1 ! -name deploy ! -name docker-compose.override.yml -exec rm -rf {} + \
  && find $APP_DIR/deploy -mindepth 1 ! -name .env ! -name tunnel.env ! -name uptime.env -exec rm -rf {} +"
git archive --format=tar HEAD | vm "tar xf - -C $APP_DIR && echo $REV > $APP_DIR/REVISION"

echo "== Building and restarting (tests run during the build)"
vm "cd $APP_DIR && if sudo docker compose -p $PROJECT up -d --build > /tmp/imjang-build.log 2>&1; then
    grep -E 'server test passed|Started|Running' /tmp/imjang-build.log | tail -4 || true
    sleep 3; sudo docker compose -p $PROJECT logs --tail 30 cloudflared 2>&1 | grep -E 'Registered tunnel connection|ERR' | tail -3 || true
  else
    tail -40 /tmp/imjang-build.log; echo '   BUILD FAILED: the old version is still running.'; exit 1
  fi"

echo "== Nightly backup"
vm "echo '50 19 * * * root $APP_DIR/deploy/vm-backup.sh daily >> /var/log/imjang-backup.log 2>&1' | sudo tee /etc/cron.d/imjang-backup >/dev/null && sudo chmod 644 /etc/cron.d/imjang-backup && sudo chmod +x $APP_DIR/deploy/vm-backup.sh && echo '   every night at 02:50 Thai time (19:50 UTC), keeping 30'"

echo "== Checking"
vm "for i in \$(seq 1 15); do curl -fs -o /dev/null http://127.0.0.1:$PORT/health && echo '   VM health 200' && exit 0; sleep 2; done; echo '   VM health FAILED'; exit 1"
code=$(curl -s -o /dev/null -w '%{http_code}' "$PUBLIC_URL/health" || true)
echo "   Public health $code"
[ "$code" = 200 ] || echo "   (If the VM said 200: check the tunnel's route imjang.cpxsim.online -> http://web:8080 in Cloudflare, or your own DNS cache.)"
echo "== Done: $REV is live"
