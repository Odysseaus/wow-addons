#!/usr/bin/env node
'use strict';
// EXPERIMENTAL macOS pixel-strip capture for WoWGrok.
//
// Same stdout JSON protocol as capture.ps1: one JSON object per line,
//   {"id":N,"text":"..."}  or  {"info":"..."} / {"warn":"..."} / {"error":"..."}.
//
//   node capture-mac.js [--cell 4] [--cells 200] [--max-rows 48]
//                       [--interval-ms 250] [--process-name WowB]
//                       [--test-image strip.png]
//
// Strategy: AppleScript (osascript) locates the Forever / World of Warcraft
// window, then `screencapture -R` grabs the top-left strip. Retina: macOS
// reports window bounds in points; screencapture writes a PNG in pixels. If
// backingScaleFactor is 2 (or the PNG is 2× the requested point size), cells
// are sampled at cellPx * scale. Requires Screen Recording permission.
//
// PNG decode is a minimal IHDR+IDAT inflater (zlib, 8-bit RGB/RGBA, no
// interlace). Zero npm dependencies. Not used on Windows (see capture.ps1).

const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const { spawnSync } = require('child_process');

function arg(name, def) {
  const i = process.argv.indexOf(name);
  if (i >= 0 && process.argv[i + 1] && !String(process.argv[i + 1]).startsWith('--')) return process.argv[i + 1];
  return def;
}

const cell = Number(arg('--cell', 4)) || 4;
const cells = Number(arg('--cells', 200)) || 200;
const maxRows = Number(arg('--max-rows', 48)) || 48;
const intervalMs = Number(arg('--interval-ms', 250)) || 250;
const processName = arg('--process-name', 'WowB') || 'WowB';
const testImage = arg('--test-image', '') || '';

function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// Minimal PNG (8-bit RGB / RGBA, non-interlaced)
// ---------------------------------------------------------------------------

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

function unfilter(data, width, height, bpp) {
  const stride = width * bpp;
  const out = Buffer.alloc(stride * height);
  let src = 0;
  for (let y = 0; y < height; y++) {
    const f = data[src++];
    const row = src;
    src += stride;
    const dst = y * stride;
    const prev = y === 0 ? null : (y - 1) * stride;
    for (let x = 0; x < stride; x++) {
      const raw = data[row + x];
      const a = x >= bpp ? out[dst + x - bpp] : 0;
      const b = prev !== null ? out[prev + x] : 0;
      const c = prev !== null && x >= bpp ? out[prev + x - bpp] : 0;
      let val;
      switch (f) {
        case 0: val = raw; break;
        case 1: val = (raw + a) & 255; break;
        case 2: val = (raw + b) & 255; break;
        case 3: val = (raw + Math.floor((a + b) / 2)) & 255; break;
        case 4: val = (raw + paeth(a, b, c)) & 255; break;
        default: throw new Error('unsupported PNG filter ' + f);
      }
      out[dst + x] = val;
    }
  }
  return out;
}

function toRgba(raw, width, height, colorType) {
  if (colorType === 6) return raw;
  if (colorType === 2) {
    const out = Buffer.alloc(width * height * 4);
    for (let i = 0, j = 0; i < raw.length; i += 3, j += 4) {
      out[j] = raw[i]; out[j + 1] = raw[i + 1]; out[j + 2] = raw[i + 2]; out[j + 3] = 255;
    }
    return out;
  }
  throw new Error('unsupported PNG color type ' + colorType);
}

function decodePng(buf) {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (!Buffer.isBuffer(buf) || buf.length < 24 || !buf.subarray(0, 8).equals(sig)) {
    throw new Error('not a PNG');
  }
  let p = 8;
  let width = 0, height = 0, bitDepth = 0, colorType = 0;
  const idats = [];
  while (p + 12 <= buf.length) {
    const len = buf.readUInt32BE(p); p += 4;
    const type = buf.toString('ascii', p, p + 4); p += 4;
    if (p + len + 4 > buf.length) throw new Error('PNG chunk truncated');
    const data = buf.subarray(p, p + len); p += len;
    p += 4; // crc
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      if (data[10] !== 0 || data[11] !== 0 || data[12] !== 0) {
        throw new Error('unsupported PNG (compression/filter/interlace)');
      }
      if (bitDepth !== 8) throw new Error('unsupported PNG bit depth ' + bitDepth);
    } else if (type === 'IDAT') {
      idats.push(data);
    } else if (type === 'IEND') break;
  }
  if (!width || !height) throw new Error('PNG missing IHDR');
  const bpp = colorType === 6 ? 4 : colorType === 2 ? 3 : 0;
  if (!bpp) throw new Error('unsupported PNG color type ' + colorType);
  const inflated = zlib.inflateSync(Buffer.concat(idats));
  const need = height * (1 + width * bpp);
  if (inflated.length < need) throw new Error('PNG IDAT truncated');
  const raw = unfilter(inflated, width, height, bpp);
  return { width, height, rgba: toRgba(raw, width, height, colorType) };
}

// ---------------------------------------------------------------------------
// 3-bit cell strip (same as capture.ps1 / Codec.lua)
// ---------------------------------------------------------------------------

function cellValue(png, c, r, cellPx, scale) {
  const side = cellPx * scale;
  const x = Math.min(png.width - 1, Math.max(0, c * side + Math.floor(side / 2)));
  const y = Math.min(png.height - 1, Math.max(0, r * side + Math.floor(side / 2)));
  const i = (y * png.width + x) * 4;
  const R = png.rgba[i], G = png.rgba[i + 1], B = png.rgba[i + 2];
  let v = 0;
  if (R >= 128) v += 4;
  if (G >= 128) v += 2;
  if (B >= 128) v += 1;
  return v;
}

function decodeStrip(png, opts) {
  const cellPx = opts.cell, nCells = opts.cells, rows = opts.maxRows, scale = opts.scale || 1;
  let acc = 0, nbits = 0;
  const bytes = [];
  let needed = 6;
  const total = nCells * rows;
  for (let i = 0; i < total; i++) {
    const c = i % nCells;
    const r = Math.floor(i / nCells);
    const v = cellValue(png, c, r, cellPx, scale);
    acc = (acc << 3) | v;
    nbits += 3;
    while (nbits >= 8) {
      bytes.push((acc >> (nbits - 8)) & 0xff);
      nbits -= 8;
      acc &= (1 << nbits) - 1;
      if (bytes.length === 2) {
        if (bytes[0] !== 0xc7 || bytes[1] !== 0x1a) return null;
      }
      if (bytes.length === 6) {
        const len = (bytes[4] * 256) + bytes[5];
        needed = 8 + len;
        if (needed > Math.floor(total * 3 / 8)) return { error: 'length' };
      }
      if (bytes.length >= needed) break;
    }
    if (bytes.length >= needed) break;
  }
  if (bytes.length < needed) return { error: 'truncated' };
  const len = (bytes[4] * 256) + bytes[5];
  let s1 = 0, s2 = 0;
  for (let k = 2; k < 6 + len; k++) {
    s1 = (s1 + bytes[k]) % 255;
    s2 = (s2 + s1) % 255;
  }
  if (bytes[6 + len] !== s1 || bytes[7 + len] !== s2) return { error: 'checksum' };
  return { id: (bytes[2] * 256) + bytes[3], text: Buffer.from(bytes.slice(6, 6 + len)).toString('utf8') };
}

function decodeFile(file, scaleHint) {
  const png = decodePng(fs.readFileSync(file));
  const logicalW = cells * cell;
  const scale = Math.max(1, Math.round(png.width / logicalW) || 1);
  return { png, scale: scaleHint && scaleHint > 1 && png.width === logicalW * scaleHint ? scaleHint : scale };
}

// ---------------------------------------------------------------------------
// macOS window + screencapture
// ---------------------------------------------------------------------------


function runOsascript(args, timeoutMs = 2500) {
  const r = spawnSync('osascript', args, {
    encoding: 'utf8',
    timeout: timeoutMs,
    killSignal: 'SIGKILL',
  });
  if (r.error) throw r.error;
  if (r.status !== 0) {
    const msg = (r.stderr || r.stdout || '').trim() || ('osascript exit ' + r.status);
    throw new Error(msg);
  }
  return (r.stdout || '').trim();
}

// Prefer CoreGraphics window list (needs Screen Recording). Avoid System Events —
// without Accessibility, System Events osascript hangs until spawnSync ETIMEDOUT.
function findWowWindow(processName) {
  const want = [];
  const add = (n) => {
    if (n && !want.includes(String(n).toLowerCase())) want.push(String(n).toLowerCase());
  };
  add(processName);
  add('World of Warcraft Beta');
  add('WowB');
  add('World of Warcraft');
  add('WowClassic');
  add('Wow');

  const jxa = `
ObjC.import('CoreGraphics');
ObjC.import('Foundation');
var opts = $.kCGWindowListOptionOnScreenOnly;
var cfArr = $.CGWindowListCopyWindowInfo(opts, $.kCGNullWindowID);
if (!cfArr) {
  'NULL_LIST';
} else {
  var js = ObjC.deepUnwrap(ObjC.castRefToObject(cfArr)) || [];
  var want = ${JSON.stringify(want)};
  var hits = [];
  for (var i = 0; i < js.length; i++) {
    var w = js[i];
    var owner = w.kCGWindowOwnerName || '';
    if ((w.kCGWindowLayer || 0) !== 0) continue;
    var low = String(owner).toLowerCase();
    var ok = false;
    for (var j = 0; j < want.length; j++) {
      if (low === want[j] || low.indexOf(want[j]) >= 0 || want[j].indexOf(low) >= 0) { ok = true; break; }
    }
    if (!ok) {
      if (low.indexOf('warcraft') < 0 && low.indexOf('wowb') < 0) continue;
    }
    var b = w.kCGWindowBounds || {};
    if (!(b.Width > 100 && b.Height > 100)) continue;
    hits.push([owner, b.X|0, b.Y|0, b.Width|0, b.Height|0].join('\t'));
  }
  hits[0] || '';
}
`;
  const out = runOsascript(['-l', 'JavaScript', '-e', jxa], 2500);
  if (out === 'NULL_LIST') {
    throw new Error('Screen Recording blocked window list — System Settings → Privacy & Security → Screen Recording → enable Terminal (or iTerm), then restart the bridge');
  }
  if (!out) return null;
  const parts = out.split('\t');
  if (parts.length < 5) return null;
  return {
    name: parts[0],
    x: Number(parts[1]),
    y: Number(parts[2]),
    w: Number(parts[3]),
    h: Number(parts[4]),
  };
}


function captureRegion(x, y, w, h, dest) {
  const r = spawnSync('screencapture', ['-x', '-t', 'png', '-R', `${Math.round(x)},${Math.round(y)},${Math.round(w)},${Math.round(h)}`, dest], {
    encoding: 'utf8', timeout: 8000,
  });
  if (r.status !== 0) {
    throw new Error(String(r.stderr || r.stdout || 'screencapture failed').trim() || 'screencapture failed');
  }
  if (!fs.existsSync(dest) || fs.statSync(dest).size < 50) {
    throw new Error('screencapture produced no image (grant Screen Recording to Terminal / node in System Settings → Privacy & Security)');
  }
}


function backingScaleFactor() {
  try {
    const r = spawnSync('osascript', ['-l', 'JavaScript', '-e',
      'ObjC.import("AppKit"); $.NSScreen.mainScreen.backingScaleFactor'], {
      encoding: 'utf8', timeout: 2000, killSignal: 'SIGKILL',
    });
    const n = parseFloat(String(r.stdout || '').trim());
    return Number.isFinite(n) && n > 0 ? n : 1;
  } catch {
    return 1;
  }
}

async function loop() {
  const dest = path.join(os.tmpdir(), 'wow-grok-strip.png');
  let lastKey = '';
  let lastWarn = 0;
  let attachedName = '';
  let toldScale = false;
  const capW = cells * cell;
  const capH = maxRows * cell;
  const declaredScale = backingScaleFactor();
  emit({ info: `experimental mac capture; backingScaleFactor=${declaredScale}; region ${capW}x${capH} points; looking for '${processName}'` });

  while (true) {
    try {
      const win = findWowWindow(processName);
      if (!win) {
        attachedName = '';
        const now = Date.now();
        if (now - lastWarn > 10000) {
          lastWarn = now;
          emit({ info: `waiting for Forever window (looked for '${processName}' and WowB / World of Warcraft). Is the game windowed/borderless and on-screen?` });
        }
        await sleep(2000);
        continue;
      }
      if (attachedName !== win.name) {
        attachedName = win.name;
        emit({ info: `attached to '${win.name}' at ${win.x},${win.y} ${win.w}x${win.h}` });
      }
      captureRegion(win.x, win.y, capW, capH, dest);
      const { png, scale } = decodeFile(dest, declaredScale);
      if (!toldScale) {
        toldScale = true;
        emit({ info: `capture bitmap ${png.width}x${png.height} px; sample scale=${scale} (cell ${cell}*${scale} px)` });
      }
      const msg = decodeStrip(png, { cell, cells, maxRows, scale });
      if (msg && msg.error) {
        const now = Date.now();
        if (now - lastWarn >= 5000) {
          lastWarn = now;
          emit({ warn: 'strip seen but rejected: ' + msg.error });
        }
      } else if (msg) {
        const key = msg.id + ':' + msg.text;
        if (key !== lastKey) {
          lastKey = key;
          emit(msg);
        }
      }
    } catch (e) {
      const msg = String(e.message || e);
      const now = Date.now();
      if (!loop._lastErr || loop._lastErr !== msg || now - (loop._lastErrAt || 0) > 15000) {
        loop._lastErr = msg;
        loop._lastErrAt = now;
        if (/ETIMEDOUT|spawnSync osascript/i.test(msg)) {
          emit({ error: 'window lookup timed out (old System Events path). Update applied — restart bridge. Also enable Screen Recording for Terminal.' });
        } else {
          emit({ error: msg });
        }
      }
      await sleep(3000);
      continue;
    }
    await sleep(intervalMs);
  }
}

if (testImage) {
  try {
    const { png, scale } = decodeFile(testImage);
    emit({ info: `test-image ${png.width}x${png.height} scale=${scale}` });
    const msg = decodeStrip(png, { cell, cells, maxRows, scale });
    if (msg && msg.error) emit(msg);
    else if (msg) emit({ id: msg.id, text: msg.text });
    else emit({ error: 'no valid strip in image' });
  } catch (e) {
    emit({ error: String(e.message || e) });
    process.exit(1);
  }
  process.exit(0);
}

if (process.platform !== 'darwin') {
  emit({ error: 'capture-mac.js is macOS only (experimental). Use capture.ps1 on Windows.' });
  process.exit(1);
}

loop().catch(e => {
  emit({ error: String(e.message || e) });
  process.exit(1);
});
