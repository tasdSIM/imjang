// Server for อิ่มจัง (Imjang): serves the app and keeps each account's save, so it follows the user to a new phone.
// No extra packages: node:http + node:sqlite + node:crypto (Node 24+). Same shape as the detective game's server.
//
//   PORT=8080 DATA_DIR=./data node server/main.js        (serves the folder above server/)
//
// API (JSON; signed-in calls send "Authorization: Bearer <token>"):
//   GET  /health                 -> "ok" when the database answers
//   GET  /api/ping               -> { ok, v } (the page uses it to learn that accounts are available here)
//   POST /api/register           { name, password, consent: true } -> { token, me }
//   POST /api/login              { name, password }  -> { token, me }
//   POST /api/logout
//   GET  /api/me                 -> { me }
//   GET  /api/save               -> { rev, ts, data } (rev 0 and data null when nothing is saved yet)
//   PUT  /api/save               { base, data }      -> { rev } or 409 { rev, ts, data } when another device saved first
//   POST /api/password           { old, password }   -> { ok } (other devices are signed out)
//   POST /api/delete             { password }        -> { ok } (account, save and sessions are gone)
//
// The save is the page's own state object (food log, weight, plan, pet …) kept as JSON. The server checks only
// its size and shape; it never reads the contents. Health data: see privacy.html.
'use strict';
const http = require('node:http'), fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');

const SESSION_DAYS = 365;
const MAX_SAVE = 1024 * 1024;        // a year of use is ~100 KB; logs are kept for 14 days
const API_V = 1;

function hashPassword(pw) {
  const salt = crypto.randomBytes(16);
  return `scrypt$${salt.toString('hex')}$${crypto.scryptSync(pw, salt, 32).toString('hex')}`;
}
function checkPassword(pw, stored) {
  const [kind, s, h] = String(stored).split('$');
  if (kind !== 'scrypt' || !s || !h) return false;
  const want = Buffer.from(h, 'hex');
  return crypto.timingSafeEqual(crypto.scryptSync(pw, Buffer.from(s, 'hex'), want.length), want);
}
const sha = t => crypto.createHash('sha256').update(t).digest('hex');

function openDb(dir) {
  fs.mkdirSync(dir, { recursive: true });
  const db = new DatabaseSync(path.join(dir, 'imjang.db'));
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=3000; PRAGMA foreign_keys=ON;
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, name_key TEXT NOT NULL UNIQUE, pw TEXT NOT NULL,
      consent INTEGER NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, created INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
    CREATE TABLE IF NOT EXISTS saves (
      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      rev INTEGER NOT NULL, ts INTEGER NOT NULL, json TEXT NOT NULL, updated INTEGER NOT NULL);`);
  return db;
}

const nameKey = n => n.normalize('NFC').toLowerCase();
function cleanName(n) {
  n = String(n || '').normalize('NFC').replace(/\s+/g, ' ').trim();
  if (n.length < 2 || n.length > 20) return [null, 'name'];
  if (/[@<>]|https?:|www\./i.test(n) || /[\u0000-\u001f]/.test(n)) return [null, 'nameChars'];
  return [n, null];
}
const okPw = pw => typeof pw === 'string' && pw.length >= 6 && pw.length <= 72;
// The page's state: an object with a pet and a food log. Nothing else is checked.
const okSave = d => d && typeof d === 'object' && !Array.isArray(d) && d.pet && typeof d.pet === 'object' && d.logs && typeof d.logs === 'object' && !Array.isArray(d.logs);
const meOf = r => ({ id: r.id, name: r.name, created: r.created });

// Errors go out as short codes; the page shows them in Thai or English.
const E = code => ({ error: code });

function createApp({ dataDir, staticDir }) {
  const db = openDb(dataDir);
  const q = {
    byId: db.prepare('SELECT * FROM users WHERE id = ?'),
    byName: db.prepare('SELECT * FROM users WHERE name_key = ?'),
    insert: db.prepare('INSERT INTO users (id, name, name_key, pw, consent, created, updated) VALUES (?, ?, ?, ?, ?, ?, ?)'),
    setPw: db.prepare('UPDATE users SET pw = ?, updated = ? WHERE id = ?'),
    delUser: db.prepare('DELETE FROM users WHERE id = ?'),
    session: db.prepare('SELECT * FROM sessions WHERE token = ?'),
    addSession: db.prepare('INSERT INTO sessions (token, user_id, created) VALUES (?, ?, ?)'),
    dropSession: db.prepare('DELETE FROM sessions WHERE token = ?'),
    dropOthers: db.prepare('DELETE FROM sessions WHERE user_id = ? AND token != ?'),
    oldSessions: db.prepare('DELETE FROM sessions WHERE created < ?'),
    save: db.prepare('SELECT rev, ts, json FROM saves WHERE user_id = ?'),
    putSave: db.prepare(`INSERT INTO saves (user_id, rev, ts, json, updated) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET rev = excluded.rev, ts = excluded.ts, json = excluded.json, updated = excluded.updated`),
  };
  q.oldSessions.run(Date.now() - SESSION_DAYS * 864e5);

  // At most 20 sign-in/sign-up/password tries per address per 15 minutes.
  const tries = new Map();
  function limited(ip) {
    const now = Date.now(), t = (tries.get(ip) || []).filter(x => now - x < 15 * 60e3);
    t.push(now); tries.set(ip, t);
    if (tries.size > 5000) for (const [k, v] of tries) if (!v.some(x => now - x < 15 * 60e3)) tries.delete(k);
    return t.length > 20;
  }
  function newSession(id) {
    const token = crypto.randomBytes(32).toString('base64url');
    q.addSession.run(sha(token), id, Date.now());
    return token;
  }
  const bearer = req => (/^Bearer (\S{20,100})$/.exec(req.headers.authorization || '') || [])[1];
  function auth(req) {
    const tok = bearer(req); if (!tok) return null;
    const s = q.session.get(sha(tok));
    if (!s || s.created < Date.now() - SESSION_DAYS * 864e5) return null;
    return q.byId.get(s.user_id) || null;
  }
  const saveOf = id => {
    const s = q.save.get(id);
    return s ? { rev: s.rev, ts: s.ts, data: JSON.parse(s.json) } : { rev: 0, ts: 0, data: null };
  };

  const routes = {
    'GET /health': () => { db.prepare('SELECT 1').get(); return [200, 'ok']; },
    'GET /api/ping': () => [200, { ok: true, v: API_V }],
    'POST /api/register': (req, b, ip) => {
      if (limited(ip)) return [429, E('tooMany')];
      const [name, err] = cleanName(b.name); if (err) return [400, E(err)];
      if (!okPw(b.password)) return [400, E('pw')];
      if (b.consent !== true) return [400, E('consent')];
      if (q.byName.get(nameKey(name))) return [409, E('taken')];
      const id = 'u_' + crypto.randomBytes(9).toString('base64url'), now = Date.now();
      q.insert.run(id, name, nameKey(name), hashPassword(b.password), now, now, now);
      return [200, { token: newSession(id), me: meOf(q.byId.get(id)) }];
    },
    'POST /api/login': (req, b, ip) => {
      if (limited(ip)) return [429, E('tooMany')];
      const r = q.byName.get(nameKey(String(b.name || '').normalize('NFC').replace(/\s+/g, ' ').trim()));
      if (!r || !checkPassword(String(b.password || ''), r.pw)) return [401, E('wrong')];
      return [200, { token: newSession(r.id), me: meOf(r) }];
    },
    'POST /api/logout': req => { const t = bearer(req); if (t) q.dropSession.run(sha(t)); return [200, { ok: true }]; },
    'GET /api/me': req => { const r = auth(req); return r ? [200, { me: meOf(r) }] : [401, E('auth')]; },
    'GET /api/save': req => { const r = auth(req); return r ? [200, saveOf(r.id)] : [401, E('auth')]; },
    'PUT /api/save': (req, b) => {
      const r = auth(req); if (!r) return [401, E('auth')];
      if (!Number.isInteger(b.base) || b.base < 0 || !okSave(b.data)) return [400, E('bad')];
      const json = JSON.stringify(b.data);
      if (json.length > MAX_SAVE) return [413, E('big')];
      let out;
      // One writer at a time per account: a save made from an older copy is refused and sent the newer one.
      db.exec('BEGIN IMMEDIATE');
      try {
        const cur = q.save.get(r.id), rev = cur ? cur.rev : 0;
        if (b.base !== rev) out = [409, saveOf(r.id)];
        else {
          const ts = Number.isFinite(b.data.ts) ? Math.round(b.data.ts) : Date.now();
          q.putSave.run(r.id, rev + 1, ts, json, Date.now());
          out = [200, { rev: rev + 1 }];
        }
        db.exec('COMMIT');
      } catch (e) { db.exec('ROLLBACK'); throw e; }
      return out;
    },
    'POST /api/password': (req, b, ip) => {
      const r = auth(req); if (!r) return [401, E('auth')];
      if (limited(ip)) return [429, E('tooMany')];
      if (!checkPassword(String(b.old || ''), r.pw)) return [400, E('oldPw')];
      if (!okPw(b.password)) return [400, E('pw')];
      q.setPw.run(hashPassword(b.password), Date.now(), r.id);
      q.dropOthers.run(r.id, sha(bearer(req)));
      return [200, { ok: true }];
    },
    'POST /api/delete': (req, b, ip) => {
      const r = auth(req); if (!r) return [401, E('auth')];
      if (limited(ip)) return [429, E('tooMany')];
      if (!checkPassword(String(b.password || ''), r.pw)) return [400, E('badPw')];
      q.delUser.run(r.id);  // sessions and the save go with it (ON DELETE CASCADE)
      return [200, { ok: true }];
    },
  };

  // ---- the app's own files (only these; never server/, deploy/, data …) ----
  const TYPES = { html: 'text/html; charset=utf-8', js: 'text/javascript; charset=utf-8', webmanifest: 'application/manifest+json',
    png: 'image/png', webp: 'image/webp', svg: 'image/svg+xml', ico: 'image/x-icon' };
  const STATIC = /^\/(index\.html|privacy\.html|sw\.js|manifest\.webmanifest|(?:icons|pet|bg)\/[\w.-]+\.(?:png|webp|svg)|vendor\/[\w.-]+\.js)$/;
  const SEC = { 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'same-origin', 'X-Frame-Options': 'SAMEORIGIN' };

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x'), key = req.method + ' ' + url.pathname;
    const send = (code, body) => {
      const json = typeof body !== 'string';
      res.writeHead(code, Object.assign({ 'Content-Type': json ? 'application/json; charset=utf-8' : 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' }, SEC));
      res.end(json ? JSON.stringify(body) : body);
    };
    if (req.method === 'GET' || req.method === 'HEAD') {
      const p = url.pathname === '/' ? '/index.html' : url.pathname, m = STATIC.exec(p);
      if (m) {
        let body; try { body = fs.readFileSync(path.join(staticDir, m[1])); } catch (e) { return send(404, E('notFound')); }
        const ext = m[1].split('.').pop();
        // pages and the service worker are checked on every visit; pictures are kept a day
        const cache = /^(html|webmanifest)$/.test(ext) || m[1] === 'sw.js' ? 'no-cache' : 'public, max-age=86400';
        res.writeHead(200, Object.assign({ 'Content-Type': TYPES[ext], 'Cache-Control': cache }, SEC));
        return res.end(req.method === 'HEAD' ? undefined : body);
      }
    }
    const fn = routes[key];
    if (!fn) return send(404, E('notFound'));
    const ip = String(req.headers['cf-connecting-ip'] || req.socket.remoteAddress || '');
    let raw = '';
    req.setEncoding('utf8');
    req.on('data', c => { raw += c; if (raw.length > MAX_SAVE + 64 * 1024) { send(413, E('big')); req.destroy(); } });
    req.on('end', () => {
      if (res.headersSent) return;
      let b = {};
      if (raw) { try { b = JSON.parse(raw); } catch (e) { return send(400, E('bad')); } }
      if (!b || typeof b !== 'object' || Array.isArray(b)) return send(400, E('bad'));
      try { const [code, body] = fn(req, b, ip); send(code, body); }
      catch (e) { console.error(key, e); send(500, E('server')); }
    });
  });
  server.on('close', () => db.close());
  return server;
}

module.exports = { createApp, openDb, hashPassword };

if (require.main === module) {
  const root = path.join(__dirname, '..');
  const port = +process.env.PORT || 8080;
  createApp({ dataDir: process.env.DATA_DIR || path.join(root, 'data'), staticDir: process.env.STATIC_DIR || root })
    .listen(port, () => console.log('imjang server on :' + port));
}
