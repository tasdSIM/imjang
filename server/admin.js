// Admin jobs, run on the VM inside the container (deploy/admin.sh wraps them):
//   node server/admin.js list                  accounts: id, name, created, last save, save size
//   node server/admin.js reset-password <id>   prints a temporary password and signs the account out everywhere
// There is no e-mail, so a forgotten password is reset here by hand after the person proves who they are.
'use strict';
const crypto = require('node:crypto'), path = require('node:path');
const { openDb, hashPassword } = require('./main.js');
const db = openDb(process.env.DATA_DIR || path.join(__dirname, '..', 'data'));
const [cmd, id] = process.argv.slice(2);
const day = t => t ? new Date(t + 7 * 3600e3).toISOString().slice(0, 16).replace('T', ' ') : '-';

if (cmd === 'list') {
  const rows = db.prepare(`SELECT u.id, u.name, u.created, s.updated, length(s.json) AS size
    FROM users u LEFT JOIN saves s ON s.user_id = u.id ORDER BY u.created`).all();
  for (const r of rows) console.log([r.id, r.name, day(r.created), day(r.updated), r.size ? Math.round(r.size / 1024) + ' KB' : '-'].join('\t'));
  console.log(rows.length + ' accounts (times are Thai time)');
} else if (cmd === 'reset-password' && id) {
  const u = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
  if (!u) { console.error('no account ' + id); process.exit(1); }
  const pw = crypto.randomBytes(6).toString('base64url');
  db.prepare('UPDATE users SET pw = ?, updated = ? WHERE id = ?').run(hashPassword(pw), Date.now(), id);
  db.prepare('DELETE FROM sessions WHERE user_id = ?').run(id);
  console.log(`temporary password for ${u.name}: ${pw}\n(tell them to change it in Settings > Account)`);
} else {
  console.error('usage: node server/admin.js list | reset-password <id>');
  process.exit(2);
}
