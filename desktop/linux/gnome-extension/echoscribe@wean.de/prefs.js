import Adw from 'gi://Adw';
import Gdk from 'gi://Gdk?version=4.0';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk?version=4.0';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';


const TRANSCRIPTION_PROVIDERS = [
    {id: 'openai', label: 'OpenAI'},
    {id: 'gemini', label: 'Gemini'},
    {id: 'xai', label: 'xAI'},
    {id: 'elevenlabs', label: 'ElevenLabs'},
];

const SUMMARY_PROVIDERS = [
    {id: 'openai', label: 'OpenAI'},
    {id: 'gemini', label: 'Gemini'},
    {id: 'anthropic', label: 'Anthropic'},
    {id: 'xai', label: 'xAI'},
];

const API_PROVIDERS = [
    {id: 'openai', label: 'OpenAI'},
    {id: 'elevenlabs', label: 'ElevenLabs'},
    {id: 'gemini', label: 'Gemini'},
    {id: 'anthropic', label: 'Anthropic'},
    {id: 'xai', label: 'xAI'},
];

const FEEDBACK_MODES = [
    {id: 'shell', label: 'GNOME Shell status', subtitle: 'Brief startup hint and compact in-shell recording states'},
    {id: 'legacy', label: 'Legacy overlay', subtitle: 'Use the sliding GTK overlay'},
    {id: 'notifications', label: 'Notifications', subtitle: 'Use desktop notifications for recording states'},
];

const MODIFIER_KEY_NAMES = new Set([
    'Shift_L',
    'Shift_R',
    'Control_L',
    'Control_R',
    'Alt_L',
    'Alt_R',
    'Meta_L',
    'Meta_R',
    'Super_L',
    'Super_R',
    'Hyper_L',
    'Hyper_R',
    'ISO_Level3_Shift',
    'ISO_Level5_Shift',
]);


export default class EchoScribePreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();

        const page = new Adw.PreferencesPage();
        window.add(page);

        const controls = new Adw.PreferencesGroup({title: 'Controls'});
        page.add(controls);

        const enabled = new Adw.SwitchRow({title: 'Enabled'});
        settings.bind('enabled', enabled, 'active', Gio.SettingsBindFlags.DEFAULT);
        controls.add(enabled);

        controls.add(shortcutRow(settings));

        const feedback = new Adw.PreferencesGroup({title: 'Feedback'});
        page.add(feedback);
        for (const row of feedbackModeRows(settings))
            feedback.add(row);

        const audio = new Adw.PreferencesGroup({title: 'Audio'});
        page.add(audio);
        const transcriptionProvider = providerRow(
            settings,
            'transcription-provider',
            TRANSCRIPTION_PROVIDERS,
            'STT Provider'
        );
        audio.add(transcriptionProvider.row);

        const webSummary = new Adw.PreferencesGroup({title: 'Web Summary'});
        page.add(webSummary);
        const summaryProvider = providerRow(
            settings,
            'summary-provider',
            SUMMARY_PROVIDERS,
            'Summary Provider'
        );
        webSummary.add(summaryProvider.row);
        for (const provider of SUMMARY_PROVIDERS)
            webSummary.add(summaryModelRow(settings, provider));

        const apiKeys = new Adw.PreferencesGroup({title: 'API-Keys'});
        page.add(apiKeys);
        for (const provider of API_PROVIDERS)
            apiKeys.add(apiKeyRow(settings, provider, () => {
                transcriptionProvider.refresh();
                summaryProvider.refresh();
            }));

        const runtime = new Adw.PreferencesGroup({title: 'Runtime'});
        page.add(runtime);

        runtime.add(boundEntryRow('Repository', settings, 'repo-path'));
        runtime.add(boundEntryRow('Python executable', settings, 'python-path'));
    }
}


function shortcutRow(settings) {
    const row = new Adw.ActionRow({title: 'PTT shortcut'});
    const label = new Gtk.ShortcutLabel({
        accelerator: primaryShortcut(settings),
        disabled_text: 'Set shortcut',
        valign: Gtk.Align.CENTER,
    });
    const button = new Gtk.Button({
        child: label,
        focus_on_click: true,
        valign: Gtk.Align.CENTER,
    });
    const keyController = new Gtk.EventControllerKey();
    let capturing = false;

    function refresh() {
        const shortcut = primaryShortcut(settings);
        label.accelerator = shortcut;
        label.disabled_text = 'Set shortcut';
        row.subtitle = legacyShortcut(shortcut);
    }

    button.connect('clicked', () => {
        capturing = true;
        label.accelerator = '';
        label.disabled_text = 'Press shortcut';
        row.subtitle = '';
        button.grab_focus();
    });

    keyController.connect('key-pressed', (controller, keyval, keycode, state) => {
        if (!capturing)
            return false;
        const keyName = Gdk.keyval_name(keyval) || '';
        if (keyName === 'Escape') {
            capturing = false;
            refresh();
            return true;
        }
        if (MODIFIER_KEY_NAMES.has(keyName))
            return true;
        const shortcut = acceleratorFromEvent(keyval, state);
        if (!shortcut)
            return true;
        settings.set_strv('toggle-shortcut', [shortcut]);
        capturing = false;
        refresh();
        return true;
    });
    button.add_controller(keyController);

    settings.connect('changed::toggle-shortcut', refresh);
    refresh();
    row.add_suffix(button);
    row.activatable_widget = button;
    return row;
}


function apiKeyRow(settings, provider, onSaved) {
    const secret = apiKeyValue(settings, provider);
    const row = new Adw.ActionRow({
        title: `${provider.label} API key`,
        subtitle: apiKeyStatusText(secret),
    });
    const entry = new Gtk.PasswordEntry({
        text: secret,
        placeholder_text: 'Paste API key',
        show_peek_icon: true,
        hexpand: true,
        valign: Gtk.Align.CENTER,
    });
    const button = new Gtk.Button({
        label: 'Save',
        valign: Gtk.Align.CENTER,
    });
    button.connect('clicked', () => {
        const value = entry.text.trim();
        if (!value)
            return;
        try {
            runEchoScribe(settings, ['config-set', 'api-key', provider.id], `${value}\n`);
            row.subtitle = apiKeyStatusText(value);
            onSaved?.();
        } catch (error) {
            logError(error);
            row.subtitle = 'Could not save API key';
        }
    });
    row.add_suffix(entry);
    row.add_suffix(button);
    row.activatable_widget = entry;
    return row;
}


function feedbackModeRows(settings) {
    const rows = [];
    const buttons = new Map();
    let group = null;
    const current = feedbackMode(settings);

    for (const mode of FEEDBACK_MODES) {
        const row = new Adw.ActionRow({
            title: mode.label,
            subtitle: mode.subtitle,
        });
        const button = new Gtk.CheckButton({
            active: mode.id === current,
            valign: Gtk.Align.CENTER,
        });
        if (group)
            button.set_group(group);
        else
            group = button;
        button.connect('toggled', () => {
            if (button.active)
                settings.set_string('feedback-mode', mode.id);
        });
        row.connect('activated', () => {
            button.active = true;
        });
        row.add_prefix(button);
        row.activatable_widget = button;
        rows.push(row);
        buttons.set(mode.id, button);
    }

    settings.connect('changed::feedback-mode', () => {
        const selected = feedbackMode(settings);
        for (const [id, button] of buttons.entries())
            button.active = id === selected;
    });

    return rows;
}


function feedbackMode(settings) {
    const mode = settings.get_string('feedback-mode') || 'shell';
    return FEEDBACK_MODES.some(item => item.id === mode) ? mode : 'shell';
}


function apiKeyStatusText(secret) {
    return secret ? 'Stored in ~/.secrets/echoscribe.env' : 'Missing API key';
}


function apiKeyValue(settings, provider) {
    try {
        return runEchoScribe(settings, ['config-get', 'api-key', provider.id]).trim();
    } catch (error) {
        logError(error);
        return '';
    }
}


function apiKeyStatus(settings, provider) {
    try {
        const status = runEchoScribe(settings, ['config-get', 'api-key-status', provider.id]).trim();
        return status === 'set' ? 'Stored in ~/.secrets/echoscribe.env' : 'Missing';
    } catch (error) {
        logError(error);
        return 'Unknown';
    }
}


function summaryModelRow(settings, provider) {
    const row = new Adw.ActionRow({
        title: `${provider.label} summary model`,
    });
    const entry = new Gtk.Entry({
        text: summaryModelValue(settings, provider),
        hexpand: true,
        valign: Gtk.Align.CENTER,
    });
    const button = new Gtk.Button({
        label: 'Save',
        valign: Gtk.Align.CENTER,
    });
    button.connect('clicked', () => {
        const value = entry.text.trim();
        if (!value)
            return;
        try {
            runEchoScribe(settings, ['config-set', 'summary-model', provider.id, value]);
            row.subtitle = 'Saved';
        } catch (error) {
            logError(error);
            row.subtitle = 'Could not save model';
        }
    });
    row.add_suffix(entry);
    row.add_suffix(button);
    row.activatable_widget = entry;
    return row;
}


function summaryModelValue(settings, provider) {
    try {
        return runEchoScribe(settings, ['config-get', 'summary-model', provider.id]).trim();
    } catch (error) {
        logError(error);
        return '';
    }
}


function providerRow(settings, configKey, providers, title) {
    const model = new Gtk.StringList();
    for (const provider of providers)
        model.append(provider.label);

    const row = new Adw.ComboRow({
        title,
        model,
    });

    let current = readProvider(settings, configKey);
    const index = providers.findIndex(provider => provider.id === current);
    row.selected = index >= 0 ? index : 0;
    refresh();

    row.connect('notify::selected', () => {
        const provider = providers[row.selected];
        if (!provider)
            return;
        try {
            runEchoScribe(settings, ['config-set', configKey, provider.id]);
            current = provider.id;
            refresh();
        } catch (error) {
            logError(error);
            row.subtitle = 'Could not save provider selection';
        }
    });

    function refresh() {
        const provider = providers.find(item => item.id === current) || providers[row.selected] || providers[0];
        const status = apiKeyStatus(settings, provider);
        row.subtitle = status === 'Stored in ~/.secrets/echoscribe.env'
            ? `${provider.label} API key stored`
            : `${provider.label} API key missing`;
    }

    return {row, refresh};
}


function readProvider(settings, configKey) {
    try {
        return runEchoScribe(settings, ['config-get', configKey]).trim() || 'openai';
    } catch (error) {
        logError(error);
        return 'openai';
    }
}


function primaryShortcut(settings) {
    const shortcuts = settings.get_strv('toggle-shortcut');
    return shortcuts.length > 0 ? shortcuts[0] : '<Super><Alt>a';
}


function acceleratorFromEvent(keyval, state) {
    const keyName = Gdk.keyval_name(keyval) || '';
    if (!keyName || MODIFIER_KEY_NAMES.has(keyName))
        return '';
    const key = keyName.length === 1 ? keyName.toLowerCase() : keyName;
    const parts = [];
    if (hasModifier(state, Gdk.ModifierType.CONTROL_MASK))
        parts.push('<Control>');
    if (hasModifier(state, Gdk.ModifierType.ALT_MASK) || hasModifier(state, Gdk.ModifierType.MOD1_MASK))
        parts.push('<Alt>');
    if (hasModifier(state, Gdk.ModifierType.SHIFT_MASK))
        parts.push('<Shift>');
    if (hasModifier(state, Gdk.ModifierType.SUPER_MASK))
        parts.push('<Super>');
    if (hasModifier(state, Gdk.ModifierType.META_MASK))
        parts.push('<Meta>');
    if (hasModifier(state, Gdk.ModifierType.HYPER_MASK))
        parts.push('<Hyper>');
    return `${parts.join('')}${key}`;
}


function hasModifier(state, mask) {
    return Number.isFinite(mask) && (state & mask) !== 0;
}


function legacyShortcut(shortcut) {
    return shortcut
        .replace(/<Super>/gi, 'super+')
        .replace(/<Primary>/gi, 'ctrl+')
        .replace(/<Control>/gi, 'ctrl+')
        .replace(/<Ctrl>/gi, 'ctrl+')
        .replace(/<Alt>/gi, 'alt+')
        .replace(/<Shift>/gi, 'shift+')
        .replace(/<Meta>/gi, 'meta+')
        .replace(/<Hyper>/gi, 'hyper+')
        .replace(/\+\+/g, '+')
        .replace(/^\+|\+$/g, '')
        .toLowerCase();
}


function runEchoScribe(settings, args, stdin = null) {
    const repoPath = settings.get_string('repo-path').trim();
    const pythonPath = settings.get_string('python-path').trim() || 'python3';
    const launcher = new Gio.SubprocessLauncher({
        flags: Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE | Gio.SubprocessFlags.STDIN_PIPE,
    });
    if (repoPath) {
        launcher.set_cwd(repoPath);
        launcher.setenv('PYTHONPATH', repoPath, true);
    }
    const proc = launcher.spawnv([pythonPath, '-m', 'echoscribe', ...args]);
    const [, stdout, stderr] = proc.communicate_utf8(stdin, null);
    if (!proc.get_successful())
        throw new Error((stderr || stdout || 'EchoScribe config command failed').trim());
    return stdout || '';
}


function boundEntryRow(title, settings, key) {
    return entryRow(title, settings.get_string(key), text => {
        settings.set_string(key, text);
    });
}


function entryRow(title, initial, onChanged) {
    const row = new Adw.ActionRow({title});
    const entry = new Gtk.Entry({
        text: initial,
        hexpand: true,
        valign: Gtk.Align.CENTER,
    });
    entry.connect('changed', () => onChanged(entry.text.trim()));
    row.add_suffix(entry);
    row.activatable_widget = entry;
    return row;
}

