#!/usr/bin/env node
'use strict';
// One-shot installer for Windows and macOS.
//
//   node setup.js [--wow "<client folder>"] [--project "<default work folder>"] [--account <name>]
//
// Finds the WoW: Forever client, copies the addon into Interface/AddOns/WoWGrok,
// writes bridge/config.json from the example (if missing), and builds the slot pool.
// Re-running is safe: existing config and generated files are kept.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = __dirname;
const ADDON_SRC = path.join(ROOT, 'addon', 'WoWGrok');
const BRIDGE = path.join(ROOT, 'bridge');
const CONFIG = path.join(BRIDGE, 'config.json');
const EXAMPLE = path.join(BRIDGE, 'config.example.json');
const FLAVORS = ['_classic_beta_', '_forever_', '_retail_', '_classic_era_', '_classic_'];

const args = {};
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a.startsWith('--')) args[a.slice(2)] = process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[++i] : true;
}

function isClient(dir) {
  try {
    if (!fs.existsSync(path.join(dir, 'Interface'))) return false;
    const names = fs.readdirSync(dir);
    if (process.platform === 'darwin') {
      if (names.some(f => /^Wow.*\.app$/i.test(f) || /^World of Warcraft.*\.app$/i.test(f))) return true;
      const macos = path.join(dir, 'Contents', 'MacOS');
      if (fs.existsSync(macos) && fs.readdirSync(macos).some(f => /^Wow/i.test(f))) return true;
      // Flavor folder that contains Interface/AddOns (WoW on Mac often looks like this).
      if (fs.existsSync(path.join(dir, 'Interface', 'AddOns'))) return true;
      return false;
    }
    return names.some(f => /^Wow.*\.exe$/i.test(f));
  } catch { return false; }
}

function coerceClient(dir) {
  dir = path.resolve(dir);
  if (isClient(dir)) return dir;
  if (/\.app$/i.test(dir) && isClient(path.dirname(dir))) return path.dirname(dir);
  for (const flavor of FLAVORS) {
    const nested = path.join(dir, flavor);
    if (isClient(nested)) return nested;
  }
  return null;
}

function findClient() {
  if (args.wow) {
    const client = coerceClient(args.wow);
    if (client) return client;
    throw new Error(`--wow "${args.wow}" does not look like a WoW client folder (needs Interface/ and a Wow*.exe, Wow*.app, or World of Warcraft*.app)`);
  }
  const roots = process.platform === 'darwin'
    ? [
      path.join(os.homedir(), 'Applications', 'World of Warcraft'),
      path.join('/Applications', 'World of Warcraft'),
    ]
    : [process.env['ProgramFiles(x86)'], process.env.ProgramFiles, 'D:\\', 'E:\\', 'D:\\Games', 'E:\\Games', 'C:\\Games']
      .filter(Boolean).map(r => path.join(r, 'World of Warcraft'));
  for (const root of roots) {
    for (const flavor of FLAVORS) {
      const dir = path.join(root, flavor);
      if (isClient(dir)) return dir;
    }
  }
  const hint = process.platform === 'darwin'
    ? 'Pass --wow "/Applications/World of Warcraft/_classic_beta_"'
    : 'Pass --wow "C:\\path\\to\\World of Warcraft\\_classic_beta_"';
  throw new Error('Could not find the WoW client. ' + hint);
}

function findAccount(client) {
  const base = path.join(client, 'WTF', 'Account');
  let names = [];
  try { names = fs.readdirSync(base).filter(n => n !== 'SavedVariables' && fs.statSync(path.join(base, n)).isDirectory()); } catch {}
  if (args.account) {
    if (!names.includes(args.account)) throw new Error(`Account "${args.account}" not found under ${base}`);
    return args.account;
  }
  if (!names.length) throw new Error(`No account folder under ${base}. Log into the game once, then run setup again.`);
  if (names.length > 1) console.log(`Several accounts found (${names.join(', ')}); using "${names[0]}". Pass --account to choose another.`);
  return names[0];
}

function copyAddon(client) {
  const dest = path.join(client, 'Interface', 'AddOns', 'WoWGrok');
  fs.mkdirSync(dest, { recursive: true });
  let copied = 0;
  for (const f of fs.readdirSync(ADDON_SRC)) {
    const target = path.join(dest, f);
    if (f === 'Inbox.lua' && fs.existsSync(target)) continue; // the bridge owns it once running
    fs.copyFileSync(path.join(ADDON_SRC, f), target);
    copied++;
  }
  return { dest, copied };
}

function detectProcessName(client) {
  let names = [];
  try { names = fs.readdirSync(client); } catch { return process.platform === 'darwin' ? 'World of Warcraft' : 'WowB'; }
  if (process.platform === 'darwin') {
    const app = names.find(f => /^WowB\.app$/i.test(f))
      || names.find(f => /^Wow.*\.app$/i.test(f))
      || names.find(f => /^World of Warcraft.*\.app$/i.test(f));
    if (app) return app.replace(/\.app$/i, '');
    for (const f of names.filter(n => /\.app$/i.test(n))) {
      try {
        const bin = fs.readdirSync(path.join(client, f, 'Contents', 'MacOS')).find(b => /^Wow/i.test(b));
        if (bin) return bin;
      } catch {}
    }
    return 'World of Warcraft';
  }
  const exe = names.find(f => /^Wow.*\.exe$/i.test(f));
  if (exe) return exe.replace(/\.exe$/i, '');
  return 'WowB';
}

function writeConfig(client, account) {
  if (fs.existsSync(CONFIG)) {
    console.log(`config   : ${CONFIG} already exists, keeping it`);
    return JSON.parse(fs.readFileSync(CONFIG, 'utf8'));
  }
  const cfg = JSON.parse(fs.readFileSync(EXAMPLE, 'utf8'));
  cfg.addonDir = path.join(client, 'Interface', 'AddOns');
  cfg.inboxFile = path.join(cfg.addonDir, 'WoWGrok', 'Inbox.lua');
  cfg.savedVariablesFile = path.join(client, 'WTF', 'Account', account, 'SavedVariables', 'WoWGrok.lua');
  cfg.defaultCwd = args.project ? path.resolve(args.project) : process.cwd();
  cfg.capture = cfg.capture || {};
  cfg.capture.processName = detectProcessName(client);
  fs.writeFileSync(CONFIG, JSON.stringify(cfg, null, 2) + '\n');
  console.log(`config   : wrote ${CONFIG}`);
  return cfg;
}

function nextSteps() {
  const mac = process.platform === 'darwin';
  const start = mac
    ? '  4. Start the bridge:  npm start'
    : '  4. Start the bridge:  npm start   (in this terminal; bridge/start-window.cmd opens its own window)';
  const extra = mac
    ? `
  macOS notes:
  - Grant Screen Recording to Terminal (or whatever runs node) in
    System Settings → Privacy & Security → Screen Recording.
  - Use windowed or borderless; exclusive fullscreen blocks capture.
  - Retina: capture-mac.js samples at backingScaleFactor (2x pixels, 2x cell size).
`
    : '';
  return `
Done. Next:
  1. Fully quit and relaunch World of Warcraft (it only discovers new addon files at launch).
  2. Enable "WoW Grok" at the character select AddOns screen (the WoW Grok slot ### entries stay enabled).
  3. Set XAI_API_KEY in the environment, or "apiKey" in bridge/config.json (never commit the key).
${start}
  5. In game:  /wow-grok
${extra}`;
}

try {
  const client = findClient();
  console.log(`client   : ${client}`);
  const account = findAccount(client);
  console.log(`account  : ${account}`);
  const { dest, copied } = copyAddon(client);
  console.log(`addon    : ${copied} file(s) -> ${dest}`);
  const cfg = writeConfig(client, account);
  console.log(`project  : ${cfg.defaultCwd}  (change with /wow-grok cd in game, or defaultCwd in config.json)`);
  console.log(`capture  : processName=${(cfg.capture && cfg.capture.processName) || 'WowB'} (${process.platform})`);
  console.log('slots    : building the reply-slot pool and signal files...');
  const r = spawnSync(process.execPath, [path.join(BRIDGE, 'install-slots.js')], { stdio: 'inherit' });
  if (r.status !== 0) throw new Error('install-slots.js failed');
  console.log(nextSteps());
} catch (e) {
  console.error('setup failed:', e.message);
  process.exit(1);
}
