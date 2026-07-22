import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';

const source = await readFile(
    new URL('../gnome-extension/echoscribe@wean.de/logic.js', import.meta.url),
    'utf8'
);
const {
    pasteKeyNames,
    startCompletionAction,
    terminalPasteShortcut,
} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);


test('terminal detection and explicit shortcut overrides', () => {
    assert.equal(terminalPasteShortcut('auto', 'org.gnome.Ptyxis'), 'ctrl+shift+v');
    assert.equal(terminalPasteShortcut('auto', 'google-chrome'), 'ctrl+v');
    assert.equal(terminalPasteShortcut('ctrl+v', 'kitty'), 'ctrl+v');
    assert.deepEqual(pasteKeyNames('ctrl+shift+v'), ['Control_L', 'Shift_L', 'v']);
    assert.deepEqual(pasteKeyNames('ctrl+v'), ['Control_L', 'v']);
});

test('second press and cancel requests during recorder startup are deterministic', () => {
    assert.equal(startCompletionAction({stopRequested: false, cancelRequested: false, enabled: true}), 'record');
    assert.equal(startCompletionAction({stopRequested: true, cancelRequested: false, enabled: true}), 'stop');
    assert.equal(startCompletionAction({stopRequested: true, cancelRequested: true, enabled: true}), 'cancel');
    assert.equal(startCompletionAction({stopRequested: false, cancelRequested: false, enabled: false}), 'cancel');
});
