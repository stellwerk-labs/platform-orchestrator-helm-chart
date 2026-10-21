#!/usr/bin/env node
// Real loopback HTTPS frames exercise the Helm-rendered policy, without a cluster.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import https from 'node:https';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
assert.ok(process.env.PLAYWRIGHT_PACKAGE_PATH,
  'Set PLAYWRIGHT_PACKAGE_PATH to an existing package.json with @playwright/test installed.');
const require = createRequire(path.resolve(process.env.PLAYWRIGHT_PACKAGE_PATH));
const { chromium } = require('@playwright/test');
const directory = await mkdtemp(path.join(os.tmpdir(), 'console-csp-browser-'));
let browser;
let hostServer;
let uiServer;

function renderedPolicy(origins) {
  const manifest = execFileSync('helm', [
    'template', 'platform-orchestrator', path.join(root, 'charts/platform-orchestrator'),
    '--set-string', 'global.gatewayApi.frontend.hostname=127.0.0.1',
    '--set-json', `console.gatewayApi.route.pluginUiOrigins=${JSON.stringify(origins)}`,
  ], { encoding: 'utf8', timeout: 30000 });
  const route = manifest.split('\n---').find(document =>
    document.includes('kind: HTTPRoute\n') &&
    document.includes('\n  name: platform-orchestrator-console\n'));
  assert.ok(route, 'render must contain Console HTTPRoute');
  return JSON.parse(route.match(/name: Content-Security-Policy\s*\n\s*value: (.+)/)[1]);
}

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve(server.address().port));
  });
}

function close(server) {
  if (!server) return Promise.resolve();
  server.closeAllConnections();
  return new Promise(resolve => server.close(resolve));
}

try {
  execFileSync('openssl', [
    'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
    '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
    '-keyout', path.join(directory, 'key.pem'), '-out', path.join(directory, 'cert.pem'),
  ], { stdio: 'ignore', timeout: 30000 });
  const tls = {
    key: await readFile(path.join(directory, 'key.pem')),
    cert: await readFile(path.join(directory, 'cert.pem')),
  };
  let hostOrigin;
  let uiOrigin;
  let policy;
  let uiRequests = 0;
  uiServer = https.createServer(tls, (request, response) => {
    uiRequests += 1;
    response.setHeader('Content-Security-Policy',
      `default-src 'self'; connect-src 'none'; script-src 'self'; frame-ancestors ${hostOrigin}`);
    response.setHeader('Cache-Control', 'no-store');
    if (request.url === '/bridge.js') {
      response.setHeader('Content-Type', 'text/javascript');
      response.end(`window.addEventListener('message', event => {
        if (event.source !== window.parent || event.origin !== ${JSON.stringify(hostOrigin)} ||
            event.data.type !== 'stellwerk.host.hello') return;
        window.parent.postMessage({type: 'stellwerk.plugin.ready', nonce: event.data.nonce},
          ${JSON.stringify(hostOrigin)});
      });`);
    } else {
      response.setHeader('Content-Type', 'text/html');
      response.end('<!doctype html><title>CSP child</title><script src="/bridge.js"></script>');
    }
  });
  const uiPort = await listen(uiServer);
  uiOrigin = `https://localhost:${uiPort}`;
  hostServer = https.createServer(tls, (_request, response) => {
    response.setHeader('Content-Security-Policy', policy);
    response.setHeader('Content-Type', 'text/html');
    response.setHeader('Cache-Control', 'no-store');
    response.end(`<!doctype html><title>CSP host</title>
      <script>window.addEventListener('securitypolicyviolation', event => {
        if (event.effectiveDirective === 'frame-src') document.documentElement.dataset.blocked = 'true';
      });</script>
      <iframe title="Plugin" sandbox="allow-scripts allow-same-origin" src="${uiOrigin}/"></iframe>
      <script>
        const frame = document.querySelector('iframe');
        const nonce = crypto.randomUUID();
        window.addEventListener('message', event => {
          if (event.source === frame.contentWindow && event.origin === ${JSON.stringify(uiOrigin)} &&
              event.data.type === 'stellwerk.plugin.ready' && event.data.nonce === nonce)
            document.documentElement.dataset.ready = 'true';
        });
        setInterval(() => frame.contentWindow.postMessage({type: 'stellwerk.host.hello', nonce},
          ${JSON.stringify(uiOrigin)}), 50);
      </script>`);
  });
  hostOrigin = `https://127.0.0.1:${await listen(hostServer)}`;
  browser = await chromium.launch();
  // The temporary certificate is used only by the two restricted loopback servers.
  const context = await browser.newContext({ ignoreHTTPSErrors: true });
  await context.route('**/*', route => {
    const origin = new URL(route.request().url()).origin;
    return origin === hostOrigin || origin === uiOrigin
      ? route.continue() : route.abort('blockedbyclient');
  });
  policy = renderedPolicy([]);
  const blocked = await context.newPage();
  await blocked.goto(hostOrigin, { waitUntil: 'load', timeout: 30000 });
  await blocked.waitForFunction(() => document.documentElement.dataset.blocked === 'true',
    undefined, { timeout: 5000 });
  assert.equal(await blocked.evaluate(() => document.documentElement.dataset.ready), undefined);
  assert.equal(uiRequests, 0, 'stock CSP must prevent even the child request');
  await blocked.close();

  policy = renderedPolicy([uiOrigin]);
  const allowed = await context.newPage();
  await allowed.goto(hostOrigin, { waitUntil: 'load', timeout: 30000 });
  await allowed.waitForFunction(() => document.documentElement.dataset.ready === 'true',
    undefined, { timeout: 5000 });
  assert.equal(await allowed.evaluate(() => document.documentElement.dataset.blocked), undefined);
  assert.ok(uiRequests >= 2, 'allowlisted child document and bridge script must load');
  console.log('PASS: rendered stock CSP blocks the frame; exact HTTPS allowance enables the cross-origin nonce handshake.');
} finally {
  await browser?.close();
  await Promise.all([close(hostServer), close(uiServer)]);
  await rm(directory, { recursive: true, force: true });
}
