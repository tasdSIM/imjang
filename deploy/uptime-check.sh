#!/usr/bin/env bash
# Checks that อิ่มจัง answers, and tells the alert LINE OA's friends when it stops (and when it
# is back). Same check as the detective game's and the executive scheduler's,
# with the site's own name in each message. It runs every 5 minutes from two places, both set up by
# deploy/install-uptime.sh: cron on the VM, and Task Scheduler on this PC, so a VM that is off or
# cut off from the internet is still noticed.
#
#   bash deploy/uptime-check.sh <config file>          # one round of checks
#   bash deploy/uptime-check.sh <config file> --test   # send a test message
#
# Config file (shell variables, kept outside git; the token is a secret):
#   LINE_ALERT_TOKEN=...            Channel access token of the alert LINE OA (the scheduler's one)
#   SOURCE="VM"                     where this check runs, shown in the message
#   CHECKS="label|url;label|url"    each must answer HTTP 200 (labels may have spaces)
#   STATE_DIR=/var/lib/...          where to remember what was already reported
#
# One failed check is not reported (a restart during deploy takes a few seconds); two in a row
# (5-10 minutes) are. While still down it reminds every 3 hours, to stay well inside the LINE OA's
# free message quota (each broadcast counts once per friend).
set -uo pipefail

CONF="${1:?usage: uptime-check.sh <config file> [--test]}"
MODE="${2:-}"
# shellcheck disable=SC1090
. "$CONF"
SOURCE="${SOURCE:-$(hostname)}"
STATE_DIR="${STATE_DIR:-$(dirname "$CONF")/uptime-state}"
REMIND_EVERY=$((3 * 3600))
LINE_API="${LINE_API:-https://api.line.me}"
mkdir -p "$STATE_DIR"

now() { date +%s; }
# Thai time is UTC+7 all year; worked out by hand because Git Bash on Windows has no time zone names.
thai_time() { date -u -d "@$(($1 + 7 * 3600))" '+%d/%m/%Y %H:%M' | awk -F/ '{ split($3, y, " "); printf "%s/%s/%d %s น.", $1, $2, y[1] + 543, y[2] }'; }
log() { echo "$(date -u -d "@$(($(now) + 7 * 3600))" '+%F %T') [$SOURCE] $*"; }
minutes() { local m=$(( ($2 - $1) / 60 )); if [ "$m" -ge 60 ]; then echo "$((m / 60)) ชม. $((m % 60)) นาที"; else echo "$m นาที"; fi; }

# JSON string for LINE (backslash, quote, newline)
json_str() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN { ORS = "" } NR > 1 { print "\\n" } { print }'; }

send_line() {
  if [ -z "${LINE_ALERT_TOKEN:-}" ]; then
    log "no LINE_ALERT_TOKEN, not sent: $(printf '%s' "$1" | head -1)"
    return 1
  fi
  local code body="$STATE_DIR/.line-body" out="$STATE_DIR/.line-out"
  # the message goes through a file: on Windows, Thai text in a command-line argument gets mangled
  printf '{"messages":[{"type":"text","text":"%s"}]}' "$(json_str "$1")" > "$body"
  code=$(curl -s -o "$out" -w '%{http_code}' --max-time 20 \
    -H "Authorization: Bearer $LINE_ALERT_TOKEN" -H 'Content-Type: application/json; charset=UTF-8' \
    --data-binary "@$body" "$LINE_API/v2/bot/message/broadcast")
  rm -f "$body"
  if [ "$code" = 200 ]; then
    log "LINE sent: $(printf '%s' "$1" | head -1)"
    rm -f "$out"
    return 0
  fi
  log "LINE failed ($code): $(cat "$out" 2>/dev/null)"
  rm -f "$out"
  return 1
}

if [ "$MODE" = --test ]; then
  send_line "🔔 ทดสอบแจ้งเตือนเว็บล่ม
ตรวจจาก: $SOURCE
เว็บที่เฝ้าดู: $(printf '%s' "$CHECKS" | tr ';' '\n' | cut -d'|' -f1 | paste -sd, - | sed 's/,/, /g')
ถ้าเห็นข้อความนี้ แปลว่าการแจ้งเตือนใช้งานได้"
  exit $?
fi

# No internet here (this machine's own network is down): say nothing rather than raise a false alarm.
if ! curl -s -o /dev/null --max-time 15 "$LINE_API/"; then
  log "no internet from here; skipped"
  exit 0
fi

IFS=';' read -ra ITEMS <<< "$CHECKS"
for item in "${ITEMS[@]}"; do
  [ -n "$item" ] || continue
  label="${item%%|*}"
  url="${item#*|}"
  key=$(printf '%s' "$label" | md5sum | cut -c1-12)
  st="$STATE_DIR/$key"
  fails=0; down_since=0; alerted=0; reminded=0
  # shellcheck disable=SC1090
  [ -f "$st" ] && . "$st"

  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$url")
  t=$(now)
  if [ "$code" = 200 ]; then
    if [ "$alerted" != 0 ]; then
      send_line "🟢 $label กลับมาใช้งานได้แล้ว
ตรวจจาก: $SOURCE
ใช้งานไม่ได้นาน $(minutes "$down_since" "$t") (ตั้งแต่ $(thai_time "$down_since"))"
    fi
    rm -f "$st"
    continue
  fi

  [ "$fails" = 0 ] && down_since=$t
  fails=$((fails + 1))
  why=$([ "$code" = 000 ] && echo "ไม่ตอบ" || echo "HTTP $code")
  [ "$code" = 530 ] && why="HTTP 530 (Cloudflare ต่อ tunnel ไม่ได้ เช่น Error 1033)"
  log "$label: $why (failure $fails)"
  if [ "$fails" -ge 2 ] && [ "$alerted" = 0 ]; then
    send_line "🔴 $label ใช้งานไม่ได้
ตรวจจาก: $SOURCE
อาการ: $why
ตั้งแต่: $(thai_time "$down_since")
$url" && alerted=$t && reminded=$t
  elif [ "$alerted" != 0 ] && [ $((t - reminded)) -ge "$REMIND_EVERY" ]; then
    send_line "🔴 $label ยังใช้งานไม่ได้
ตรวจจาก: $SOURCE
อาการ: $why
นานแล้ว $(minutes "$down_since" "$t")" && reminded=$t
  fi
  printf 'fails=%s\ndown_since=%s\nalerted=%s\nreminded=%s\n' "$fails" "$down_since" "$alerted" "$reminded" > "$st"
done
