import assert from 'node:assert/strict';
import { notificationSequence, wrapForTmux } from '../../../.config/pi/agent/extensions/notify.ts';

const kitty = notificationSequence('Pi', 'Done', { KITTY_WINDOW_ID: '1' });
assert.match(kitty, /^\x1b\]99;/);
assert.ok(kitty.includes(':d=0;Pi\x1b\\'));
assert.ok(kitty.includes(':p=body;Done\x1b\\'));
const wezterm = notificationSequence('Pi', 'Done', { TERM_PROGRAM: 'WezTerm' });
assert.equal(wezterm, '\x1b]777;notify;Pi;Done\x07');
assert.match(notificationSequence('Pi', 'Done', { TERM: 'xterm-kitty' }), /^\x1b\]99;/);
const wrapped = wrapForTmux(kitty, { TMUX: 'test' });
assert.ok(wrapped.startsWith('\x1bPtmux;\x1b\x1b]99;'));
assert.ok(wrapped.endsWith('\x1b\\'));
assert.equal(wrapForTmux(kitty, {}), kitty);
const hostile = notificationSequence('Pi;test', 'hello\x07\x1b]52;bad\ntext', {});
assert.equal((hostile.match(/\x07/g) || []).length, 1);
assert.equal((hostile.match(/\x1b/g) || []).length, 1);
assert.ok(!hostile.includes('Pi;test'));
console.log('Notification protocol/routing/sanitization checks passed. No notification was sent.');
