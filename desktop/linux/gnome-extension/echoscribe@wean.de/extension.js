import Gio from 'gi://Gio';
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';
import {
    pasteKeyNames,
    startCompletionAction,
    terminalPasteShortcut,
} from './logic.js';


const SHORTCUT_SETTING = 'toggle-shortcut';
// Mutter keybinding names are global across all extensions. Keep the public
// toggle-shortcut setting for compatibility, but register a namespaced key.
const KEYBINDING_SETTING = 'echoscribe-toggle-shortcut';
const FEEDBACK_MODES = new Set(['shell', 'notifications']);
const TERMINAL_STATE_MS = 4200;
const STARTUP_HINT_MS = 2600;
const PHASE = Object.freeze({
    IDLE: 'idle',
    STARTING: 'starting',
    RECORDING: 'recording',
    PROCESSING: 'processing',
});
const STATE_ICON = {
    idle: 'audio-input-microphone-symbolic',
    starting: 'view-refresh-symbolic',
    recording: 'media-record-symbolic',
    processing: 'view-refresh-symbolic',
    pasting: 'edit-paste-symbolic',
    done: 'emblem-ok-symbolic',
    error: 'dialog-error-symbolic',
};
const STATE_TITLE = {
    idle: 'Ready',
    starting: 'Starting recorder',
    recording: 'Recording',
    processing: 'Transcribing',
    pasting: 'Pasting',
    done: 'Done',
    error: 'Error',
};
const EchoScribeShellStatus = GObject.registerClass(
class EchoScribeShellStatus extends St.BoxLayout {
    _init() {
        super._init({
            style_class: 'echoscribe-shell-status',
            vertical: false,
            reactive: false,
            style: 'padding: 12px 18px; spacing: 12px;',
        });
        this._icon = new St.Icon({icon_name: STATE_ICON.idle, icon_size: 26});
        this._label = new St.Label({
            text: STATE_TITLE.idle,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this.add_child(this._icon);
        this.add_child(this._label);
        this.set_size(280, 58);
        this.hide();
    }

    setState(state, message) {
        this._icon.icon_name = STATE_ICON[state] ?? STATE_ICON.idle;
        this._label.text = message || STATE_TITLE[state] || STATE_TITLE.idle;
        this.set_style_class_name(`echoscribe-shell-status echoscribe-${state}`);
        this._reposition();
    }

    setVisibleNow(visible) {
        if (!visible) {
            this.hide();
            return;
        }
        this.show();
        GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            this._reposition();
            return GLib.SOURCE_REMOVE;
        });
    }

    _reposition() {
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor)
            return;
        const width = Math.max(this.width || 0, 280);
        this.set_position(monitor.x + monitor.width - width - 24, monitor.y + 78);
    }
});


const EchoScribeQuickToggle = GObject.registerClass(
class EchoScribeQuickToggle extends QuickSettings.QuickMenuToggle {
    _init(extensionObject) {
        super._init({
            title: 'EchoScribe',
            subtitle: STATE_TITLE.idle,
            iconName: STATE_ICON.idle,
            toggleMode: false,
        });
        this._extensionObject = extensionObject;
        this._destroyed = false;
        this.connect('clicked', () => this._extensionObject.primaryAction());
        this.menu.setHeader(STATE_ICON.idle, 'EchoScribe', STATE_TITLE.idle);
        this._toggleItem = this.menu.addAction('Start Dictation', () => this._extensionObject.primaryAction());
        this._cancelItem = this.menu.addAction('Cancel', () => this._extensionObject.cancelDictation());
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._quitItem = this.menu.addAction('Disable EchoScribe', () => this._extensionObject.quitEchoScribe());
        const settingsItem = this.menu.addAction('Open Preferences…', () => {
            try {
                const opened = this._extensionObject.openPreferences();
                opened?.catch?.(error => logError(error));
            } catch (error) {
                logError(error);
            }
        });
        settingsItem.visible = Main.sessionMode.allowSettings;
        this.menu._settingsActions[extensionObject.uuid] = settingsItem;
        this._cancelItem.visible = false;
    }

    setState(state, message, enabled = true) {
        if (this._destroyed)
            return;
        const title = enabled ? message || STATE_TITLE[state] || STATE_TITLE.idle : 'Off';
        const icon = STATE_ICON[state] ?? STATE_ICON.idle;
        this.subtitle = title;
        this.iconName = icon;
        this.checked = enabled && [PHASE.STARTING, PHASE.RECORDING, PHASE.PROCESSING].includes(state);
        this._toggleItem.label.text = enabled && state !== PHASE.IDLE ? 'Stop Dictation' : 'Start Dictation';
        this._cancelItem.visible = enabled && state !== PHASE.IDLE;
        this._quitItem.visible = enabled;
        this.menu.setHeader(icon, 'EchoScribe', title);
    }

    destroy() {
        this._destroyed = true;
        super.destroy();
    }
});


const EchoScribeSystemIndicator = GObject.registerClass(
class EchoScribeSystemIndicator extends QuickSettings.SystemIndicator {
    _init(extensionObject) {
        super._init();
        this._toggle = new EchoScribeQuickToggle(extensionObject);
        this.quickSettingsItems.push(this._toggle);
    }

    setState(state, message, enabled = true) {
        this._toggle?.setState(state, message, enabled);
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        this.quickSettingsItems = [];
        this._toggle = null;
        super.destroy();
    }
});


export default class EchoScribeExtension extends Extension {
    enable() {
        this._destroyed = false;
        this._settings = this.getSettings();
        this._shortcutBound = false;
        this._syncKeybindingSetting();
        this._phase = PHASE.IDLE;
        this._recordingId = '';
        this._stopRequested = false;
        this._cancelRequested = false;
        this._settingsSignals = [];
        this._timers = new Set();
        this._processes = new Map();
        this._ignoredProcesses = new Set();
        this._virtualKeyboard = null;
        this._pressedVirtualKeys = [];
        this._lastErrorClipboard = '';
        this._pythonPath = this._settings.get_string('python-path').trim() || '/usr/bin/python3';
        this._installPath = this._settings.get_string('install-path').trim();

        this._indicator = new EchoScribeSystemIndicator(this);
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
        this._shellStatus = new EchoScribeShellStatus();
        Main.uiGroup.add_child(this._shellStatus);

        this._bindShortcut();
        this._settingsSignals.push(this._settings.connect('changed::enabled', () => this._syncEnabled()));
        this._settingsSignals.push(this._settings.connect('changed::toggle-shortcut', () => this._rebindShortcut()));
        this._settingsSignals.push(this._settings.connect('changed::feedback-mode', () => this._showStartupHint()));
        this._settingsSignals.push(this._settings.connect('changed::install-path', () => {
            this._installPath = this._settings.get_string('install-path').trim();
        }));
        this._settingsSignals.push(this._settings.connect('changed::python-path', () => {
            this._pythonPath = this._settings.get_string('python-path').trim() || '/usr/bin/python3';
        }));
        this._syncEnabled();
        this._showStartupHint();
        this._runWorker('status', '', payload => this._handleStartupStatus(payload));
    }

    disable() {
        const cleanupArgs = this._workerArgs('cancel', this._recordingId);
        this._destroyed = true;
        this._unbindShortcut();
        this._clearTimers();
        this._releaseVirtualKeys();
        this._virtualKeyboard = null;
        this._settingsSignals.forEach(id => this._settings?.disconnect(id));
        this._settingsSignals = [];

        if (this._phase === PHASE.STARTING) {
            // The start callback chains a cancel after it learns the recording_id.
        } else if (this._phase !== PHASE.IDLE) {
            this._spawnCleanupCancel(cleanupArgs);
        } else {
            this._terminateTrackedProcesses();
        }

        if (this._shellStatus) {
            Main.uiGroup.remove_child(this._shellStatus);
            this._shellStatus.destroy();
            this._shellStatus = null;
        }
        this._indicator?.destroy();
        this._indicator = null;
        this._settings = null;
        this._phase = PHASE.IDLE;
        this._recordingId = '';
    }

    primaryAction() {
        if (!this._settings)
            return;
        if (!this._settings.get_boolean('enabled')) {
            this._settings.set_boolean('enabled', true);
            return;
        }
        if (this._phase === PHASE.IDLE)
            this._beginRecording();
        else if (this._phase === PHASE.RECORDING)
            this._requestStop();
        else if (this._phase === PHASE.STARTING)
            this._stopRequested = true;
    }

    cancelDictation() {
        if (!this._settings || this._phase === PHASE.IDLE)
            return;
        this._cancelRequested = true;
        if (this._phase === PHASE.STARTING && !this._recordingId) {
            this._setState(PHASE.PROCESSING, 'Canceling', false);
            return;
        }
        const id = this._recordingId;
        this._clearRecordingReminder();
        this._runWorker('cancel', id, payload => {
            this._terminateAction('stop');
            this._recordingId = '';
            this._stopRequested = false;
            this._cancelRequested = false;
            this._phase = PHASE.IDLE;
            this._setState(PHASE.IDLE, payload.message || 'Canceled', true);
        }, error => this._showError(error));
    }

    quitEchoScribe() {
        this.cancelDictation();
        this._settings?.set_boolean('enabled', false);
    }


    _bindShortcut() {
        if (!this._settings?.get_boolean('enabled'))
            return;
        try {
            const handler = () => this._onShortcutTriggered();
            const modes = Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW;
            // Some GNOME 50 distributions expose the window manager helper
            // with Mutter's four-argument signature. Register against the
            // stable Mutter API directly and preserve Shell action modes.
            const action = global.display.add_keybinding(
                KEYBINDING_SETTING,
                this._settings,
                Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
                handler
            );
            if (action === Meta.KeyBindingAction.NONE) {
                throw new Error(`Could not register shortcut ${this._primaryShortcut()}`);
            }
            Main.wm.allowKeybinding(KEYBINDING_SETTING, modes);
            this._shortcutBound = true;
        } catch (error) {
            this._shortcutBound = false;
            this._showError(error);
        }
    }

    _unbindShortcut() {
        if (!this._shortcutBound)
            return;
        try {
            if (global.display.remove_keybinding(KEYBINDING_SETTING))
                Main.wm.allowKeybinding(KEYBINDING_SETTING, Shell.ActionMode.NONE);
        } catch (error) {
            console.debug(`EchoScribe keybinding cleanup: ${error}`);
        }
        this._shortcutBound = false;
    }

    _rebindShortcut() {
        this._syncKeybindingSetting();
        this._unbindShortcut();
        this._bindShortcut();
        this._showStartupHint();
    }

    _syncKeybindingSetting() {
        const shortcuts = this._settings?.get_strv(SHORTCUT_SETTING) ?? [];
        const effective = shortcuts.length > 0 ? shortcuts : ['<Super><Alt>a'];
        const registered = this._settings?.get_strv(KEYBINDING_SETTING) ?? [];
        if (effective.length !== registered.length ||
            effective.some((shortcut, index) => shortcut !== registered[index]))
            this._settings?.set_strv(KEYBINDING_SETTING, effective);
    }

    _syncEnabled() {
        const enabled = this._settings?.get_boolean('enabled') ?? false;
        if (enabled && !this._shortcutBound)
            this._bindShortcut();
        if (!enabled && this._shortcutBound)
            this._unbindShortcut();
        if (!enabled && this._phase !== PHASE.IDLE)
            this.cancelDictation();
        this._indicator?.setState(enabled ? this._phase : PHASE.IDLE, enabled ? '' : 'Off', enabled);
        this._updateShellVisibility();
    }

    _onShortcutTriggered() {
        if (!this._settings?.get_boolean('enabled'))
            return;
        if (this._phase === PHASE.IDLE) {
            this._beginRecording();
        } else if (this._phase === PHASE.STARTING) {
            this._stopRequested = true;
        } else if (this._phase === PHASE.RECORDING) {
            this._requestStop();
        }
    }

    _beginRecording() {
        if (this._phase !== PHASE.IDLE)
            return;
        this._phase = PHASE.STARTING;
        this._recordingId = '';
        this._stopRequested = false;
        this._cancelRequested = false;
        this._setState(PHASE.STARTING, STATE_TITLE.starting, true);
        this._runWorker('start', '', payload => {
            if (!payload.ok) {
                this._resetToIdle();
                this._showError(payload.message);
                return;
            }
            this._recordingId = String(payload.recording_id || '');
            const completionAction = startCompletionAction({
                stopRequested: this._stopRequested,
                cancelRequested: this._cancelRequested,
                enabled: this._settings?.get_boolean('enabled') ?? false,
            });
            if (completionAction === 'cancel') {
                this._runWorker('cancel', this._recordingId, () => this._resetToIdle(), error => {
                    this._resetToIdle();
                    this._showError(error);
                });
                return;
            }
            this._phase = PHASE.RECORDING;
            this._setState(PHASE.RECORDING, this._recordingMessage(), true);
            this._scheduleRecordingReminder(Number(payload.reminder_seconds || 0));
            if (completionAction === 'stop')
                this._requestStop();
        }, error => {
            this._resetToIdle();
            this._showError(error);
        });
    }

    _requestStop() {
        if (this._phase !== PHASE.RECORDING)
            return;
        this._clearRecordingReminder();
        this._phase = PHASE.PROCESSING;
        this._setState(PHASE.PROCESSING, STATE_TITLE.processing, true);
        const id = this._recordingId;
        this._runWorker('stop', id, payload => {
            this._recordingId = '';
            if (!payload.ok) {
                this._resetToIdle();
                this._showError(payload.message);
                return;
            }
            this._pasteTranscript(payload);
        }, error => {
            this._resetToIdle();
            this._showError(error);
        });
    }

    _scheduleRecordingReminder(seconds) {
        this._clearRecordingReminder();
        if (!(seconds > 0))
            return;
        this._reminderTimer = this._addTimer(Math.max(1, Math.round(seconds * 1000)), () => {
            this._reminderTimer = 0;
            if (this._phase === PHASE.RECORDING)
                Main.notify('EchoScribe', `Still recording — press ${this._primaryShortcut()} to stop`);
        });
    }

    _clearRecordingReminder() {
        if (this._reminderTimer)
            this._removeTimer(this._reminderTimer);
        this._reminderTimer = 0;
    }

    _recordingMessage() {
        return `Recording — ${this._primaryShortcut()} stops`;
    }

    _pasteTranscript(payload) {
        const transcript = String(payload.transcript || '');
        if (!transcript) {
            this._resetToIdle();
            this._showError('Transcription returned empty text');
            return;
        }
        try {
            St.Clipboard.get_default().set_text(St.ClipboardType.CLIPBOARD, transcript);
        } catch (error) {
            this._resetToIdle();
            this._showError(`Could not copy transcript: ${error}`);
            return;
        }
        this._setState('pasting', STATE_TITLE.pasting, true);
        const delay = Math.max(0, Number(payload.paste_delay_ms || 0));
        this._addTimer(delay, () => {
            try {
                this._injectPaste(terminalPasteShortcut(payload.paste_shortcut, this._focusedAppDescription()));
                this._phase = PHASE.IDLE;
                this._setState('done', 'Pasted', true);
            } catch (error) {
                this._phase = PHASE.IDLE;
                this._showError(`Paste failed; transcript remains in the clipboard. ${error}`, false);
            }
            this._scheduleTerminalHide();
        });
    }

    _injectPaste(shortcut) {
        if (!this._virtualKeyboard) {
            const seat = Clutter.get_default_backend().get_default_seat();
            this._virtualKeyboard = seat.create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);
        }
        const keys = pasteKeyNames(shortcut).map(name => Clutter[`KEY_${name}`]);
        const now = () => GLib.get_monotonic_time();
        this._pressedVirtualKeys = [];
        try {
            for (const key of keys) {
                this._virtualKeyboard.notify_keyval(now(), key, Clutter.KeyState.PRESSED);
                this._pressedVirtualKeys.push(key);
            }
            for (const key of [...keys].reverse()) {
                this._virtualKeyboard.notify_keyval(now(), key, Clutter.KeyState.RELEASED);
                this._pressedVirtualKeys.pop();
            }
        } finally {
            this._releaseVirtualKeys();
        }
    }

    _releaseVirtualKeys() {
        if (!this._virtualKeyboard)
            return;
        for (const key of [...this._pressedVirtualKeys].reverse()) {
            try {
                this._virtualKeyboard.notify_keyval(GLib.get_monotonic_time(), key, Clutter.KeyState.RELEASED);
            } catch (error) {
                console.debug(`EchoScribe virtual key cleanup: ${error}`);
            }
        }
        this._pressedVirtualKeys = [];
    }

    _focusedAppDescription() {
        let window = null;
        try {
            window = global.display.focus_window || global.display.get_focus_window?.();
        } catch (error) {
            console.debug(`EchoScribe focus lookup: ${error}`);
        }
        if (!window)
            return '';
        const values = [];
        const add = value => {
            const text = String(value || '').trim();
            if (text)
                values.push(text);
        };
        try {
            const app = Shell.WindowTracker.get_default().get_window_app(window);
            add(app?.get_id?.());
            add(app?.get_name?.());
        } catch (error) {
            console.debug(`EchoScribe app lookup: ${error}`);
        }
        for (const method of ['get_gtk_application_id', 'get_wm_class', 'get_wm_class_instance', 'get_sandboxed_app_id']) {
            try {
                add(window[method]?.());
            } catch (error) {
                console.debug(`EchoScribe focus ${method}: ${error}`);
            }
        }
        return values.join(' ');
    }

    _handleStartupStatus(payload) {
        if (!payload?.ok && payload?.state === 'error') {
            // Error states are persisted so an interrupted recording can be
            // diagnosed. On a later login they are historical, though: show no
            // stale failure toast and reset the worker for the next dictation.
            this._recordingId = String(payload.recording_id || '');
            this._runWorker('cancel', this._recordingId, () => this._resetToIdle(), error => this._showError(error));
            return;
        }
        if (payload?.state === PHASE.RECORDING || payload?.state === PHASE.PROCESSING) {
            this._recordingId = String(payload.recording_id || '');
            this._phase = PHASE.PROCESSING;
            this._setState(PHASE.PROCESSING, 'Cleaning previous session', false);
            this._runWorker('cancel', this._recordingId, () => this._resetToIdle(), error => {
                this._resetToIdle();
                this._showError(error);
            });
        }
    }

    _resetToIdle() {
        this._clearRecordingReminder();
        this._phase = PHASE.IDLE;
        this._recordingId = '';
        this._stopRequested = false;
        this._cancelRequested = false;
        this._setState(PHASE.IDLE, STATE_TITLE.idle, false);
    }

    _setState(state, message, notify) {
        if (this._destroyed || !this._settings)
            return;
        const enabled = this._settings.get_boolean('enabled');
        this._indicator?.setState(state, message, enabled);
        this._shellStatus?.setState(state, message);
        this._shellStatus?.setVisibleNow(enabled && this._usesShellWidget() && state !== PHASE.IDLE);
        if (notify && enabled && this._usesNotifications())
            Main.notify('EchoScribe', message || STATE_TITLE[state] || state);
    }

    _showError(error, copyToClipboard = true) {
        const raw = String(error?.message || error || 'Unknown error').trim();
        const message = raw.startsWith('[ECHOSCRIBE ERROR]') ? raw : `[ECHOSCRIBE ERROR] ${raw}`;
        if (copyToClipboard && message !== this._lastErrorClipboard) {
            this._lastErrorClipboard = message;
            try {
                St.Clipboard.get_default().set_text(St.ClipboardType.CLIPBOARD, message);
            } catch (clipboardError) {
                logError(clipboardError);
            }
        }
        this._setState('error', message, true);
        if (!this._usesNotifications())
            Main.notify('EchoScribe', message);
        this._scheduleTerminalHide();
    }

    _scheduleTerminalHide() {
        this._addTimer(TERMINAL_STATE_MS, () => {
            if (this._phase === PHASE.IDLE)
                this._setState(PHASE.IDLE, STATE_TITLE.idle, false);
        });
    }

    _showStartupHint() {
        if (!this._settings || !this._settings.get_boolean('enabled') || !this._shortcutBound || !this._usesShellWidget()) {
            this._updateShellVisibility();
            return;
        }
        this._shellStatus?.setState(PHASE.IDLE, this._primaryShortcut());
        this._shellStatus?.setVisibleNow(true);
        this._addTimer(STARTUP_HINT_MS, () => this._updateShellVisibility());
    }

    _updateShellVisibility() {
        const visible = Boolean(this._settings?.get_boolean('enabled')) && this._usesShellWidget() && this._phase !== PHASE.IDLE;
        this._shellStatus?.setVisibleNow(visible);
    }

    _usesShellWidget() {
        return this._feedbackMode() === 'shell';
    }

    _usesNotifications() {
        return this._feedbackMode() === 'notifications';
    }

    _feedbackMode() {
        const mode = this._settings?.get_string('feedback-mode') || 'shell';
        return FEEDBACK_MODES.has(mode) ? mode : 'shell';
    }

    _primaryShortcut() {
        return this._settings?.get_strv(SHORTCUT_SETTING)?.[0] || '<Super><Alt>a';
    }

    _workerArgs(action, recordingId = '') {
        const python = this._pythonPath || '/usr/bin/python3';
        const args = [python, '-m', 'echoscribe', 'gnome-worker', action, '--json'];
        if (recordingId)
            args.push('--recording-id', recordingId);
        return args;
    }

    _launcher() {
        const installPath = this._installPath || '';
        const launcher = new Gio.SubprocessLauncher({
            flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
        });
        launcher.set_environ(GLib.get_environ());
        if (installPath) {
            launcher.set_cwd(installPath);
            launcher.setenv('PYTHONPATH', installPath, true);
        }
        return launcher;
    }

    _runWorker(action, recordingId, onSuccess, onFailure = null) {
        if (!this._settings || this._destroyed)
            return;
        let proc;
        try {
            proc = this._launcher().spawnv(this._workerArgs(action, recordingId));
            this._processes.set(proc, action);
        } catch (error) {
            onFailure?.(error);
            return;
        }
        proc.communicate_utf8_async(null, null, (source, result) => {
            this._processes.delete(source);
            try {
                const [, stdout, stderr] = source.communicate_utf8_finish(result);
                if (this._ignoredProcesses.delete(source))
                    return;
                const payload = JSON.parse((stdout || '{}').trim() || '{}');
                if (this._destroyed) {
                    if (action === 'start' && payload.ok && payload.recording_id)
                        this._spawnCleanupCancel(this._workerArgs('cancel', String(payload.recording_id)));
                    else if (action === 'start')
                        this._terminateTrackedProcesses();
                    return;
                }
                if (!source.get_successful() && payload.ok !== false)
                    throw new Error((stderr || stdout || 'EchoScribe worker failed').trim());
                onSuccess?.(payload);
            } catch (error) {
                onFailure?.(error);
            }
        });
    }

    _runProjectScript(argv, successMessage) {
        if (!this._settings || this._destroyed)
            return;
        let proc;
        try {
            proc = this._launcher().spawnv(argv);
            this._processes.set(proc, 'script');
        } catch (error) {
            this._showError(error);
            return;
        }
        proc.communicate_utf8_async(null, null, (source, result) => {
            this._processes.delete(source);
            if (this._destroyed)
                return;
            try {
                const [, stdout, stderr] = source.communicate_utf8_finish(result);
                if (!source.get_successful())
                    throw new Error((stderr || stdout || 'Command failed').trim());
                if (successMessage)
                    Main.notify('EchoScribe', successMessage);
            } catch (error) {
                this._showError(error);
            }
        });
    }

    _spawnCleanupCancel(argv) {
        let proc;
        try {
            proc = this._launcher().spawnv(argv);
        } catch (error) {
            console.debug(`EchoScribe disable cancel: ${error}`);
            this._terminateTrackedProcesses();
            return;
        }
        proc.wait_async(null, (source, result) => {
            try {
                source.wait_finish(result);
            } catch (error) {
                console.debug(`EchoScribe disable cancel wait: ${error}`);
            }
            this._terminateTrackedProcesses();
        });
    }

    _terminateTrackedProcesses() {
        for (const proc of this._processes.keys()) {
            try {
                if (!proc.get_if_exited())
                    proc.force_exit();
            } catch (error) {
                console.debug(`EchoScribe subprocess cleanup: ${error}`);
            }
        }
        this._processes.clear();
    }

    _terminateAction(action) {
        for (const [proc, procAction] of this._processes) {
            if (procAction !== action)
                continue;
            try {
                if (!proc.get_if_exited())
                    proc.force_exit();
            } catch (error) {
                console.debug(`EchoScribe ${action} cleanup: ${error}`);
            }
            this._ignoredProcesses.add(proc);
            this._processes.delete(proc);
        }
    }

    _addTimer(delay, callback) {
        let id = 0;
        id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, Math.max(1, Math.round(delay)), () => {
            this._timers.delete(id);
            callback();
            return GLib.SOURCE_REMOVE;
        });
        this._timers.add(id);
        return id;
    }

    _removeTimer(id) {
        if (!id)
            return;
        GLib.source_remove(id);
        this._timers.delete(id);
    }

    _clearTimers() {
        for (const id of this._timers)
            GLib.source_remove(id);
        this._timers.clear();
        this._reminderTimer = 0;
    }
}
