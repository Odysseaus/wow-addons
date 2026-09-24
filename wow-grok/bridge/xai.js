'use strict';
// Talk to the xAI Grok API (Responses). Zero npm deps; Node 20+ global fetch.
//
//   POST {apiBase}/responses     default apiBase https://api.x.ai/v1
//   Auth: Authorization: Bearer <XAI_API_KEY or cfg.apiKey>   (never logged)
//
// Valid model ids include grok-4, grok-4-latest, grok-4.6, and whatever else
// xAI currently serves. Default is grok-4-latest.
//
// Multi-turn: pass previousResponseId (the prior response's `id`) so the
// server continues that stored conversation. If that id is rejected, chat()
// retries once without it, sending `history` (local {role,content} turns) as
// the full input instead.

const DEFAULT_MODEL = 'grok-4-latest';
const DEFAULT_BASE = 'https://api.x.ai/v1';

function extractText(data) {
  if (!data || typeof data !== 'object') return '';
  if (typeof data.output_text === 'string' && data.output_text.trim()) return data.output_text;
  const parts = [];
  const take = (c) => {
    if (!c) return;
    if (typeof c === 'string') { if (c) parts.push(c); return; }
    if (typeof c.text === 'string') parts.push(c.text);
    else if (typeof c.output_text === 'string') parts.push(c.output_text);
  };
  for (const item of Array.isArray(data.output) ? data.output : []) {
    if (!item) continue;
    if (typeof item === 'string') { parts.push(item); continue; }
    if (item.type === 'output_text' || item.type === 'text') { take(item); continue; }
    const isMsg = item.type === 'message' || item.role === 'assistant';
    if (!isMsg && item.type && item.type !== 'message') continue;
    if (typeof item.content === 'string') take(item.content);
    else if (Array.isArray(item.content)) item.content.forEach(take);
    else take(item);
  }
  return parts.join('\n').trim();
}

function apiErrorMessage(status, data, raw) {
  const err = data && (data.error || data);
  const msg = err && (err.message || err.error || (typeof err === 'string' ? err : null));
  if (typeof msg === 'string' && msg.trim()) return `xAI API HTTP ${status}: ${msg.trim()}`;
  const snippet = String(raw || '').replace(/Bearer\s+\S+/gi, 'Bearer [redacted]').slice(0, 400);
  return `xAI API HTTP ${status}${snippet ? ': ' + snippet : ''}`;
}

function isPreviousResponseError(err) {
  const st = err && err.status;
  if (st === 400 || st === 404) return true;
  const m = String((err && err.message) || err || '').toLowerCase();
  return /previous[_ ]response|not found|unknown response|expired|invalid.*response/.test(m);
}

function asUserInput(input) {
  if (typeof input === 'string') return input;
  if (Array.isArray(input)) return input;
  if (input && typeof input === 'object' && (input.content || input.role)) return [input];
  return String(input ?? '');
}

function toInputMessages(history, input) {
  const msgs = [];
  for (const m of history || []) {
    if (!m) continue;
    const role = (m.role === 'assistant' || m.role === 'grok') ? 'assistant' : 'user';
    const content = m.content != null ? m.content : m.text;
    if (content == null || content === '') continue;
    msgs.push({ role, content: String(content) });
  }
  if (typeof input === 'string') {
    if (input) msgs.push({ role: 'user', content: input });
  } else if (Array.isArray(input)) {
    for (const item of input) {
      if (!item) continue;
      if (typeof item === 'string') msgs.push({ role: 'user', content: item });
      else msgs.push(item);
    }
  } else if (input && typeof input === 'object') {
    msgs.push(input);
  }
  return msgs;
}

async function postResponse({ apiKey, model, apiBase, input, previousResponseId, system, signal }) {
  const base = String(apiBase || DEFAULT_BASE).replace(/\/$/, '');
  const url = base + '/responses';
  const body = {
    model: model || DEFAULT_MODEL,
    input,
    store: true,
  };
  if (previousResponseId) body.previous_response_id = previousResponseId;
  else if (system) body.instructions = system;

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer ' + apiKey,
    },
    body: JSON.stringify(body),
    signal,
  });
  const raw = await res.text();
  let data = null;
  try { data = JSON.parse(raw); } catch { /* non-JSON error page */ }
  if (!res.ok) {
    const err = new Error(apiErrorMessage(res.status, data, raw));
    err.status = res.status;
    throw err;
  }
  if (!data || typeof data !== 'object') throw new Error('xAI API returned non-JSON');
  const text = extractText(data);
  const id = data.id || '';
  if (!id && !text) throw new Error('xAI API returned an empty response');
  return { id, text: text || '' };
}

/**
 * @param {object} opts
 * @param {string} [opts.apiKey]
 * @param {string} [opts.model]
 * @param {string} [opts.apiBase]
 * @param {string|Array} opts.input
 * @param {string} [opts.previousResponseId]
 * @param {string} [opts.system]
 * @param {AbortSignal} [opts.signal]
 * @param {function} [opts.onProgress]  heartbeat while the request is in flight
 * @param {Array<{role:string,content:string}>} [opts.history]  local fallback turns
 * @returns {Promise<{id:string,text:string}>}
 */
async function chat(opts = {}) {
  const apiKey = opts.apiKey || process.env.XAI_API_KEY || '';
  if (!apiKey) {
    throw new Error('Missing xAI API key. Set the XAI_API_KEY environment variable or "apiKey" in bridge/config.json.');
  }
  const model = opts.model || DEFAULT_MODEL;
  const onProgress = opts.onProgress;
  let beat;
  if (typeof onProgress === 'function') {
    try { onProgress(); } catch { /* listener errors must not fail the request */ }
    beat = setInterval(() => { try { onProgress(); } catch {} }, 20000);
  }
  try {
    const input = asUserInput(opts.input);
    try {
      return await postResponse({
        apiKey,
        model,
        apiBase: opts.apiBase,
        input,
        previousResponseId: opts.previousResponseId || undefined,
        system: opts.system,
        signal: opts.signal,
      });
    } catch (err) {
      if (!opts.previousResponseId || !isPreviousResponseError(err)) throw err;
      const fallback = toInputMessages(opts.history, opts.input);
      return await postResponse({
        apiKey,
        model,
        apiBase: opts.apiBase,
        input: fallback.length ? fallback : input,
        previousResponseId: undefined,
        system: opts.system,
        signal: opts.signal,
      });
    }
  } finally {
    if (beat) clearInterval(beat);
  }
}

module.exports = { chat, extractText, DEFAULT_MODEL, DEFAULT_BASE };
