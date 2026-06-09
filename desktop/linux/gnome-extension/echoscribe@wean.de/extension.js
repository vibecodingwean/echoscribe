import Gio from 'gi://Gio';
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';


const STATE_ICON = {
    idle: 'audio-input-microphone-symbolic',
    recording: 'media-record-symbolic',
    processing: 'view-refresh-symbolic',
    pasting: 'edit-paste-symbolic',
    done: 'emblem-ok-symbolic',
    error: 'dialog-error-symbolic',
};

const STATE_TITLE = {
    idle: 'Ready',
    recording: 'Recording',
    processing: 'Transcribing',
    pasting: 'Pasting',
    done: 'Done',
    error: 'Error',
};

const STARTUP_HINT_MS = 2600;
const TERMINAL_STATE_MS = 4200;
const TERMINAL_STATES = new Set(['done', 'error']);
const FEEDBACK_MODES = new Set(['shell', 'legacy', 'notifications']);


const EchoScribeSideband = GObject.registerClass(
class EchoScribeSideband extends St.BoxLayout {
    _init() {
        super._init({
            style_class: 'echoscribe-sideband',
            vertical: false,
            reactive: false,
            style: 'padding: 12px 18px; spacing: 12px;',
        });
        this._icon = new St.Icon({
            icon_name: STATE_ICON.idle,
            icon_size: 26,
            style: 'color: #2563eb;',
        });
        this._label = new St.Label({
            text: STATE_TITLE.idle,
            style: 'color: #0f172a; font-weight: 700; font-size: 15px;',
            y_align: Clutter.ActorAlign.CENTER,
        });
        this.add_child(this._icon);
        this.add_child(this._label);
        this.set_size(260, 58);
        this.hide();
    }

    setState(state, message) {
        this._icon.icon_name = STATE_ICON[state] ?? STATE_ICON.idle;
        this._label.text = message || STATE_TITLE[state] || STATE_TITLE.idle;
        this._icon.style = state === 'recording'
            ? 'color: #dc2626;'
            : state === 'error'
                ? 'color: #b91c1c;'
                : 'color: #2563eb;';
        this._reposition();
    }

    setVisibleNow(visible) {
        if (visible) {
            this.show();
            GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                this._reposition();
                return GLib.SOURCE_REMOVE;
            });
        } else {
            this.hide();
        }
    }

    _reposition() {
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor)
            return;
        const width = Math.max(this.width || 0, 260);
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
        this.connect('clicked', () => this._extensionObject.primaryAction());

        this.menu.setHeader(STATE_ICON.idle, 'EchoScribe', STATE_TITLE.idle);
        this._toggleItem = this.menu.addAction('Start Dictation', () => {
            this._extensionObject.primaryAction();
        });
        this._cancelItem = this.menu.addAction('Cancel', () => {
            this._extensionObject.cancelDictation();
        });
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._browserItem = this.menu.addAction('Chrome Plugin installieren / registrieren', () => {
            this._extensionObject.installBrowserPlugin();
        });
        this._extensionsItem = this.menu.addAction('chrome://extensions oeffnen', () => {
            this._extensionObject.openChromeExtensions();
        });
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._quitItem = this.menu.addAction('Quit EchoScribe', () => {
            this._extensionObject.quitEchoScribe();
        });
        const settingsItem = this.menu.addAction('Einstellungen...', () => {
            try {
                const result = this._extensionObject.openPreferences();
                if (result && typeof result.catch === 'function')
                    result.catch(error => logError(error));
            } catch (error) {
                logError(error);
            }
        });
        settingsItem.visible = Main.sessionMode.allowSettings;
        this.menu._settingsActions[extensionObject.uuid] = settingsItem;
        this._cancelItem.visible = false;
        this._destroyed = false;
    }

    setState(state, message, enabled = true) {
        if (this._destroyed)
            return;
        const title = enabled ? message || STATE_TITLE[state] || STATE_TITLE.idle : 'Off';
        const icon = STATE_ICON[state] ?? STATE_ICON.idle;
        this.subtitle = title;
        this.iconName = icon;
        this.checked = enabled && (state === 'recording' || state === 'processing');
        this._toggleItem.label.text = enabled
            ? state === 'recording' ? 'Stop Dictation' : 'Start Dictation'
            : 'Enable EchoScribe';
        this._cancelItem.visible = enabled && (state === 'recording' || state === 'processing');
        this._browserItem.visible = enabled;
        this._extensionsItem.visible = enabled;
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
        this._destroyed = false;
    }

    setState(state, message, enabled = true) {
        if (this._destroyed || !this._toggle)
            return;
        this._toggle.setState(state, message, enabled);
    }

    destroy() {
        this._destroyed = true;
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
        this._state = 'idle';
        this._lastNotificationState = '';
        this._statusInFlight = false;
        this._settingsSignals = [];
        this._errorHideTimer = 0;
        this._startupHintTimer = 0;
        this._sidebandHintActive = false;
        this._stateUpdatedAt = 0;
        this._lastErrorClipboardKey = '';
        this._focusSignal = 0;
        this._focusHintPath = this._buildFocusHintPath();

        this._indicator = new EchoScribeSystemIndicator(this);
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
        this._sideband = new EchoScribeSideband();
        Main.uiGroup.add_child(this._sideband);
        try {
            this._focusSignal = global.display.connect('notify::focus-window', () => this._writeFocusHint());
        } catch (error) {
            logError(error);
        }
        this._writeFocusHint();

        this._settingsSignals.push(this._settings.connect('changed::enabled', () => this._syncEnabled()));
        this._settingsSignals.push(this._settings.connect('changed::toggle-shortcut', () => {
            this._syncSideband();
            this._showStartupHint();
        }));
        this._settingsSignals.push(this._settings.connect('changed::feedback-mode', () => {
            this._syncSideband();
            this._showStartupHint();
        }));
        this._syncEnabled();
        this._syncSideband();
        this._showStartupHint();

        this._statusTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 650, () => {
            this.refreshStatus();
            return GLib.SOURCE_CONTINUE;
        });
        this.refreshStatus();
    }

    disable() {
        this._destroyed = true;
        if (this._statusTimer) {
            GLib.source_remove(this._statusTimer);
            this._statusTimer = 0;
        }
        if (this._errorHideTimer) {
            GLib.source_remove(this._errorHideTimer);
            this._errorHideTimer = 0;
        }
        if (this._startupHintTimer) {
            GLib.source_remove(this._startupHintTimer);
            this._startupHintTimer = 0;
        }
        if (this._focusSignal) {
            try {
                global.display.disconnect(this._focusSignal);
            } catch (error) {
                logError(error);
            }
            this._focusSignal = 0;
        }
        this._sidebandHintActive = false;
        this._runSideband('stop');
        this._settingsSignals?.forEach(id => this._settings.disconnect(id));
        this._settingsSignals = [];
        if (this._sideband) {
            Main.uiGroup.remove_child(this._sideband);
            this._sideband.destroy();
            this._sideband = null;
        }
        this._indicator?.destroy();
        this._indicator = null;
        this._settings = null;
    }

    primaryAction() {
        if (!this._settings)
            return;
        if (!this._settings.get_boolean('enabled')) {
            this._settings.set_boolean('enabled', true);
            return;
        }
        this.toggleDictation();
    }

    toggleDictation() {
        if (!this._settings)
            return;
        if (!this._settings.get_boolean('enabled'))
            return;
        this._runWorker('toggle', payload => this._handleWorkerPayload(payload, true));
    }

    cancelDictation() {
        if (!this._settings)
            return;
        this._runWorker('cancel', payload => this._handleWorkerPayload(payload, true));
    }

    quitEchoScribe() {
        if (!this._settings)
            return;
        this.cancelDictation();
        this._settings.set_boolean('enabled', false);
        this._syncEnabled();
    }

    installBrowserPlugin() {
        this._runProjectScript(['./scripts/register_chrome_host.sh'], 'Browser Plugin registriert');
    }

    openChromeExtensions() {
        this._runProjectScript(['xdg-open', 'chrome://extensions'], '');
    }

    refreshStatus() {
        if (!this._settings)
            return;
        if (this._statusInFlight)
            return;
        this._statusInFlight = true;
        this._runWorker('status', payload => {
            this._statusInFlight = false;
            this._handleWorkerPayload(payload, false);
        }, () => {
            this._statusInFlight = false;
        });
    }

    _syncEnabled() {
        if (!this._settings)
            return;
        const enabled = this._settings.get_boolean('enabled');
        this._indicator?.setState(enabled ? this._state : 'idle', enabled ? '' : 'Off', enabled);
        this._syncSideband();
    }

    _syncSideband() {
        if (!this._settings || this._destroyed)
            return;
        const enabled = this._settings.get_boolean('enabled');
        const headless = !this._usesLegacyOverlay();
        if (enabled)
            this._runSideband('start', headless);
        else
            this._runSideband('stop');
        const state = this._state || 'idle';
        this._sideband?.setState(state, state === 'idle' ? this._shortcutLabel() : '');
        this._updateSidebandVisibility();
    }

    _updateSidebandVisibility() {
        if (!this._sideband || !this._settings || this._destroyed)
            return;
        const enabled = this._settings.get_boolean('enabled');
        const shellWidget = this._usesShellWidget();
        const state = this._state || 'idle';

        let shouldBeVisible = false;
        if (enabled && shellWidget) {
            shouldBeVisible = this._sidebandHintActive && state === 'idle';
            if (!shouldBeVisible && state !== 'idle')
                shouldBeVisible = !this._stateIsExpired(state);
        }
        this._sideband.setVisibleNow(shouldBeVisible);
    }

    _handleWorkerPayload(payload, notify) {
        if (!payload || !this._settings || this._destroyed)
            return;
        const state = payload.state || 'idle';
        const message = payload.message || STATE_TITLE[state] || STATE_TITLE.idle;
        const enabled = this._settings.get_boolean('enabled');
        this._state = state;
        this._stateUpdatedAt = Number(payload.updated_at || 0);
        this._indicator?.setState(state, message, enabled);
        const shellWidget = this._usesShellWidget();
        if (shellWidget)
            this._sideband?.setState(state, state === 'idle' ? this._shortcutLabel() : message);

        this._updateSidebandVisibility();

        if (shellWidget && state === 'error')
            this._copyErrorToClipboard(message);

        if (shellWidget && TERMINAL_STATES.has(state) && !this._stateIsExpired(state)) {
            if (this._errorHideTimer) {
                GLib.source_remove(this._errorHideTimer);
                this._errorHideTimer = 0;
            }
            const hideDelay = Math.max(250, TERMINAL_STATE_MS - this._stateAgeMs());
            this._errorHideTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, hideDelay, () => {
                this._errorHideTimer = 0;
                if (TERMINAL_STATES.has(this._state) && !this._destroyed)
                    this._updateSidebandVisibility();
                return GLib.SOURCE_REMOVE;
            });
        }

        if (this._usesNotifications() && enabled && (notify || ['recording', 'processing', 'pasting', 'done', 'error'].includes(state)))
            this._notifyState(state, message);
    }

    _usesShellWidget() {
        return this._feedbackMode() === 'shell';
    }

    _usesNotifications() {
        return this._feedbackMode() === 'notifications';
    }

    _usesLegacyOverlay() {
        return this._feedbackMode() === 'legacy';
    }

    _feedbackMode() {
        const mode = this._settings?.get_string('feedback-mode') || 'shell';
        return FEEDBACK_MODES.has(mode) ? mode : 'shell';
    }

    _showStartupHint() {
        if (!this._settings || this._destroyed)
            return;
        if (!this._settings.get_boolean('enabled') || !this._usesShellWidget()) {
            this._sidebandHintActive = false;
            this._updateSidebandVisibility();
            return;
        }
        if (this._startupHintTimer) {
            GLib.source_remove(this._startupHintTimer);
            this._startupHintTimer = 0;
        }
        this._sidebandHintActive = true;
        this._sideband?.setState('idle', this._shortcutLabel());
        this._updateSidebandVisibility();
        this._startupHintTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, STARTUP_HINT_MS, () => {
            this._startupHintTimer = 0;
            this._sidebandHintActive = false;
            this._updateSidebandVisibility();
            return GLib.SOURCE_REMOVE;
        });
    }

    _stateIsExpired(state) {
        if (!TERMINAL_STATES.has(state))
            return false;
        if (!this._stateUpdatedAt)
            return false;
        return this._stateAgeMs() >= TERMINAL_STATE_MS;
    }

    _stateAgeMs() {
        if (!this._stateUpdatedAt)
            return 0;
        return (Date.now() / 1000 - this._stateUpdatedAt) * 1000;
    }

    _copyErrorToClipboard(message) {
        const text = String(message || '').trim();
        if (!text)
            return;
        const key = `${this._stateUpdatedAt}:${text}`;
        if (key === this._lastErrorClipboardKey)
            return;
        this._lastErrorClipboardKey = key;
        try {
            St.Clipboard.get_default().set_text(St.ClipboardType.CLIPBOARD, text);
        } catch (error) {
            logError(error);
        }
    }

    _notifyState(state, message) {
        if (state === this._lastNotificationState && state !== 'error')
            return;
        this._lastNotificationState = state;
        Main.notify('EchoScribe', message);
    }

    _runWorker(action, onSuccess, onFailure = null) {
        if (!this._settings || this._destroyed)
            return;
        let argv;
        try {
            argv = this._workerArgs(action);
        } catch (error) {
            logError(error);
            onFailure?.(error);
            return;
        }

        const repoPath = this._settings.get_string('repo-path').trim();
        const launcher = new Gio.SubprocessLauncher({
            flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
        });
        launcher.set_environ(GLib.get_environ());
        this._applyFocusHintEnv(launcher, true);
        if (repoPath) {
            launcher.set_cwd(repoPath);
            launcher.setenv('PYTHONPATH', repoPath, true);
        }

        let proc;
        try {
            proc = launcher.spawnv(argv);
        } catch (error) {
            logError(error);
            onFailure?.(error);
            return;
        }

        proc.communicate_utf8_async(null, null, (source, result) => {
            try {
                const [, stdout, stderr] = source.communicate_utf8_finish(result);
                if (stderr)
                    console.debug(`EchoScribe worker stderr: ${stderr.trim()}`);
                const payload = JSON.parse((stdout || '{}').trim() || '{}');
                onSuccess?.(payload);
            } catch (error) {
                logError(error);
                onFailure?.(error);
            }
        });
    }

    _runProjectScript(argv, successMessage) {
        if (!this._settings || this._destroyed)
            return;
        const repoPath = this._settings.get_string('repo-path').trim();
        const launcher = new Gio.SubprocessLauncher({
            flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
        });
        launcher.set_environ(GLib.get_environ());
        if (repoPath)
            launcher.set_cwd(repoPath);
        let proc;
        try {
            proc = launcher.spawnv(argv);
        } catch (error) {
            logError(error);
            Main.notify('EchoScribe', String(error));
            return;
        }
        proc.communicate_utf8_async(null, null, (source, result) => {
            try {
                const [, stdout, stderr] = source.communicate_utf8_finish(result);
                const message = (stderr || stdout || '').trim();
                if (!source.get_successful()) {
                    Main.notify('EchoScribe', message || 'Befehl fehlgeschlagen');
                    return;
                }
                if (successMessage)
                    Main.notify('EchoScribe', successMessage);
            } catch (error) {
                logError(error);
                Main.notify('EchoScribe', String(error));
            }
        });
    }

    _workerArgs(action) {
        const pythonPath = this._settings.get_string('python-path').trim() || 'python3';
        return [pythonPath, '-m', 'echoscribe', 'gnome-worker', action, '--json'];
    }

    _buildFocusHintPath() {
        const stateHome = GLib.getenv('XDG_STATE_HOME')
            || GLib.build_filenamev([GLib.get_home_dir(), '.local', 'state']);
        return GLib.build_filenamev([stateHome, 'echoscribe', 'focus-app-hint']);
    }

    _applyFocusHintEnv(launcher, directHint = false) {
        const hint = this._writeFocusHint();
        const path = this._focusHintPath || this._buildFocusHintPath();
        launcher.setenv('ECHOSCRIBE_GNOME_FOCUS_HINT_FILE', path, true);
        launcher.setenv('ECHOSCRIBE_TRUST_GNOME_FOCUS_HINT', '1', true);
        if (directHint && hint)
            launcher.setenv('ECHOSCRIBE_ACTIVE_APP_HINT', hint, true);
    }

    _writeFocusHint() {
        const hint = this._focusedAppHint();
        try {
            const path = this._focusHintPath || this._buildFocusHintPath();
            GLib.mkdir_with_parents(GLib.path_get_dirname(path), 0o700);
            GLib.file_set_contents(path, hint);
        } catch (error) {
            console.debug(`EchoScribe focus hint failed: ${error}`);
        }
        return hint;
    }

    _focusedAppHint() {
        let window = null;
        try {
            window = global.display?.focus_window || global.display?.get_focus_window?.();
        } catch (error) {
            console.debug(`EchoScribe focus window unavailable: ${error}`);
        }
        if (!window)
            return '';

        const parts = [];
        const add = (label, value) => {
            const text = String(value || '').trim();
            if (text)
                parts.push(`${label}=${text}`);
        };
        const read = (label, method) => {
            try {
                if (typeof window[method] === 'function')
                    add(label, window[method]());
            } catch (error) {
                console.debug(`EchoScribe focus ${method} failed: ${error}`);
            }
        };

        try {
            const app = Shell.WindowTracker.get_default().get_window_app(window);
            add('shell-app-id', app?.get_id?.());
            add('shell-app-name', app?.get_name?.());
        } catch (error) {
            console.debug(`EchoScribe focus app lookup failed: ${error}`);
        }
        read('app-id', 'get_gtk_application_id');
        read('wm-class', 'get_wm_class');
        read('wm-class-instance', 'get_wm_class_instance');
        read('sandboxed-app-id', 'get_sandboxed_app_id');
        read('title', 'get_title');
        return parts.join(' ');
    }

    _runSideband(action, headless = false) {
        if (!this._settings)
            return;
        const repoPath = this._settings.get_string('repo-path').trim();
        const pythonPath = this._settings.get_string('python-path').trim() || 'python3';
        const launcher = new Gio.SubprocessLauncher({
            flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
        });
        launcher.set_environ(GLib.get_environ());
        this._applyFocusHintEnv(launcher, false);
        if (repoPath) {
            launcher.set_cwd(repoPath);
            launcher.setenv('PYTHONPATH', repoPath, true);
        }
        if (action === 'start') {
            launcher.setenv('ECHOSCRIBE_DICTATION_HOLD', this._legacyShortcut(), true);
            if (headless)
                launcher.setenv('ECHOSCRIBE_HEADLESS_OVERLAY', '1', true);
        }
        let proc;
        try {
            let argv;
            if (action === 'start') {
                const headlessFlag = headless ? ' --headless' : '';
                argv = ['sg', 'input', '-c', `${pythonPath} -m echoscribe sideband start --json${headlessFlag}`];
            } else {
                argv = [pythonPath, '-m', 'echoscribe', 'sideband', action, '--json'];
            }
            proc = launcher.spawnv(argv);
        } catch (error) {
            logError(error);
            return;
        }
        proc.communicate_utf8_async(null, null, (source, result) => {
            try {
                const [, , stderr] = source.communicate_utf8_finish(result);
                if (stderr)
                    console.debug(`EchoScribe sideband stderr: ${stderr.trim()}`);
            } catch (error) {
                logError(error);
            }
        });
    }

    _legacyShortcut() {
        if (!this._settings)
            return 'super+alt+a';
        const shortcut = this._primaryShortcut();
        return shortcut
            .replace(/<Super>/gi, 'super+')
            .replace(/<Primary>/gi, 'ctrl+')
            .replace(/<Control>/gi, 'ctrl+')
            .replace(/<Ctrl>/gi, 'ctrl+')
            .replace(/<Alt>/gi, 'alt+')
            .replace(/<Shift>/gi, 'shift+')
            .replace(/\+\+/g, '+')
            .replace(/^\+|\+$/g, '')
            .toLowerCase();
    }

    _shortcutLabel() {
        return this._settings?.get_strv('toggle-shortcut').join(', ') || '<Super><Alt>a';
    }

    _primaryShortcut() {
        return this._settings?.get_strv('toggle-shortcut')[0] || '<Super><Alt>a';
    }
}

