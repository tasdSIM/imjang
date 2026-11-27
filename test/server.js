// Runs the real server on a spare port with an empty database and checks accounts and saves.
//   node test/server.js        (Node 24+; also run while building the Docker image)
'use strict';
const assert = require('node:assert/strict'), fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { createApp } = require('../server/main.js');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'imjang-test-'));
const app = createApp({ dataDir: dir, staticDir: path.join(__dirname, '..') });

app.listen(0, async () => {
  const base = 'http://127.0.0.1:' + app.address().port;
  const call = async (method, p, body, tok) => {
    const r = await fetch(base + p, { method, headers: Object.assign({ 'Content-Type': 'application/json' }, tok ? { Authorization: 'Bearer ' + tok } : {}),
      body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await r.text();
    let j = null; try { j = JSON.parse(text); } catch (e) {}
    return { status: r.status, j, text, type: r.headers.get('content-type') || '', cache: r.headers.get('cache-control') };
  };
  const save = (name, extra) => Object.assign({ pet: { sp: 'cat', name }, logs: { '2026-11-27': [{ n: 'x', k: 500 }] }, ts: Date.now() }, extra);
  let n = 0; const ok = (c, m) => { assert.ok(c, m); n++; };
  try {
    // the app's files, and nothing else
    let r = await call('GET', '/');
    ok(r.status === 200 && r.type.startsWith('text/html') && r.text.includes('imjang'), 'serves the page at /');
    ok(r.cache === 'no-cache', 'page is revalidated');
    ok((await call('GET', '/sw.js')).cache === 'no-cache', 'service worker is revalidated');
    ok((await call('GET', '/manifest.webmanifest')).status === 200, 'manifest');
    ok((await call('GET', '/icons/icon-192.png')).type === 'image/png', 'icon');
    ok((await call('GET', '/pet/cat-1-happy.webp')).type === 'image/webp', 'pet art');
    ok((await call('GET', '/privacy.html')).status === 200, 'privacy page');
    ok((await call('GET', '/vendor/zxing-library-0.21.3.min.js')).type.startsWith('text/javascript'), 'barcode reader script');
    for (const p of ['/server/main.js', '/test/server.js', '/deploy/deploy-vm.sh', '/Dockerfile', '/data/imjang.db', '/.git/config', '/pet/../server/main.js', '/README.md'])
      ok((await call('GET', p)).status === 404, 'hidden: ' + p);
    ok((await call('GET', '/health')).text === 'ok', 'health');
    ok((await call('GET', '/api/ping')).j.ok === true, 'ping');

    // sign up
    ok((await call('POST', '/api/register', { name: 'a', password: 'secret1', consent: true })).j.error === 'name', 'name too short');
    ok((await call('POST', '/api/register', { name: 'me@x.com', password: 'secret1', consent: true })).j.error === 'nameChars', 'no e-mail as name');
    ok((await call('POST', '/api/register', { name: 'มะลิ', password: '123', consent: true })).j.error === 'pw', 'password too short');
    ok((await call('POST', '/api/register', { name: 'มะลิ', password: 'secret1' })).j.error === 'consent', 'consent required');
    r = await call('POST', '/api/register', { name: '  มะลิ  Cat ', password: 'secret1', consent: true });
    ok(r.status === 200 && r.j.me.name === 'มะลิ Cat' && r.j.token, 'registered');
    const A = r.j.token;
    ok((await call('POST', '/api/register', { name: 'มะลิ cat', password: 'secret2', consent: true })).status === 409, 'name taken (any case)');

    // sign in
    ok((await call('POST', '/api/login', { name: 'มะลิ cat', password: 'nope' })).status === 401, 'wrong password');
    r = await call('POST', '/api/login', { name: 'มะลิ CAT', password: 'secret1' });
    ok(r.status === 200, 'login'); const B = r.j.token;   // a second device
    ok((await call('GET', '/api/me', undefined, A)).j.me.name === 'มะลิ Cat', 'me');
    ok((await call('GET', '/api/me', undefined, 'x'.repeat(40))).status === 401, 'bad token');

    // saves: first write, then a second device that is behind gets 409 with the newer copy
    r = await call('GET', '/api/save', undefined, A);
    ok(r.j.rev === 0 && r.j.data === null, 'empty save');
    ok((await call('PUT', '/api/save', { base: 0, data: { nope: 1 } }, A)).status === 400, 'save shape checked');
    r = await call('PUT', '/api/save', { base: 0, data: save('Mali') }, A);
    ok(r.status === 200 && r.j.rev === 1, 'first save');
    r = await call('PUT', '/api/save', { base: 0, data: save('Other') }, B);
    ok(r.status === 409 && r.j.rev === 1 && r.j.data.pet.name === 'Mali', 'stale save refused with the newer copy');
    r = await call('PUT', '/api/save', { base: 1, data: save('Both') }, B);
    ok(r.status === 200 && r.j.rev === 2, 'save after catching up');
    ok((await call('GET', '/api/save', undefined, A)).j.data.pet.name === 'Both', 'other device reads it');
    ok((await call('PUT', '/api/save', { base: 2, data: save('Big', { pad: 'x'.repeat(1100 * 1024) }) }, A)).status === 413, 'too big');

    // password change signs the other device out
    ok((await call('POST', '/api/password', { old: 'bad', password: 'secret9' }, A)).j.error === 'oldPw', 'old password checked');
    ok((await call('POST', '/api/password', { old: 'secret1', password: 'secret9' }, A)).status === 200, 'password changed');
    ok((await call('GET', '/api/me', undefined, B)).status === 401, 'other device signed out');
    ok((await call('GET', '/api/me', undefined, A)).status === 200, 'this device still in');

    // logout
    ok((await call('POST', '/api/logout', {}, A)).status === 200 && (await call('GET', '/api/me', undefined, A)).status === 401, 'logout');

    // delete: needs the password, then the account, its save and sessions are gone
    const C = (await call('POST', '/api/login', { name: 'มะลิ cat', password: 'secret9' })).j.token;
    ok((await call('POST', '/api/delete', { password: 'wrong' }, C)).j.error === 'badPw', 'delete needs the password');
    ok((await call('POST', '/api/delete', { password: 'secret9' }, C)).status === 200, 'deleted');
    ok((await call('GET', '/api/me', undefined, C)).status === 401, 'session gone');
    ok((await call('POST', '/api/login', { name: 'มะลิ cat', password: 'secret9' })).status === 401, 'account gone');
    r = await call('POST', '/api/register', { name: 'มะลิ cat', password: 'secret1', consent: true });
    ok(r.status === 200 && (await call('GET', '/api/save', undefined, r.j.token)).j.rev === 0, 'name free again, old save not inherited');

    // too many tries from one address
    let last;
    for (let i = 0; i < 20; i++) last = await call('POST', '/api/login', { name: 'nobody', password: 'xxxxxx' });
    ok(last.status === 429, 'sign-in tries are limited');

    console.log(`server test passed (${n} checks)`);
  } catch (e) {
    console.error('server test FAILED:', e.message); process.exitCode = 1;
  } finally {
    // the database closes when the server has closed; only then can Windows remove its folder
    app.close(() => { try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {} });
    app.closeAllConnections();
  }
});
