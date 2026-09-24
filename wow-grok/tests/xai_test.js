'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const xai = require('../bridge/xai');

test('extractText prefers output_text then message content output_text', () => {
  assert.equal(xai.extractText({ output_text: 'plain' }), 'plain');
  assert.equal(xai.extractText({
    output: [{
      type: 'message',
      role: 'assistant',
      content: [{ type: 'output_text', text: 'from cells' }],
    }],
  }), 'from cells');
  assert.equal(xai.extractText({
    output: [
      { type: 'reasoning', summary: [{ text: 'ignored' }] },
      { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'hello' }, { type: 'output_text', text: 'world' }] },
    ],
  }), 'hello\nworld');
});

test('chat throws a clear error when the API key is missing', async () => {
  const prev = process.env.XAI_API_KEY;
  delete process.env.XAI_API_KEY;
  await assert.rejects(() => xai.chat({ input: 'hi', apiKey: '' }), /XAI_API_KEY|apiKey/);
  if (prev !== undefined) process.env.XAI_API_KEY = prev;
});
