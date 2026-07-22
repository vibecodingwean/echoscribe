const TERMINAL_PATTERN = /(^|[.\s_-])(terminal|console|ptyxis|kgx|konsole|tilix|xterm|kitty|alacritty|wezterm|foot)([.\s_-]|$)/i;


export function terminalPasteShortcut(configured, focusedApp) {
    const shortcut = String(configured || 'auto').toLowerCase();
    if (shortcut === 'ctrl+shift+v')
        return 'ctrl+shift+v';
    if (shortcut === 'ctrl+v')
        return 'ctrl+v';
    return TERMINAL_PATTERN.test(String(focusedApp || '')) ? 'ctrl+shift+v' : 'ctrl+v';
}


export function pasteKeyNames(shortcut) {
    return shortcut === 'ctrl+shift+v'
        ? ['Control_L', 'Shift_L', 'v']
        : ['Control_L', 'v'];
}


export function startCompletionAction({stopRequested, cancelRequested, enabled}) {
    if (cancelRequested || !enabled)
        return 'cancel';
    return stopRequested ? 'stop' : 'record';
}
