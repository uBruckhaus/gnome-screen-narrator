// Requests to the reader through backend/bridge.py (one JSON line in, one out), the same
// bridge the Omarchy popup used. It starts the reader service when needed and runs setup.
// Used by the shell and by the settings window, so only Gio and GLib here.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

Gio._promisify(Gio.Subprocess.prototype, 'communicate_utf8_async');
Gio._promisify(Gio.SocketConnection.prototype, 'close_async');
Gio._promisify(Gio.SocketClient.prototype, 'connect_async');
Gio._promisify(Gio.OutputStream.prototype, 'write_all_async');
Gio._promisify(Gio.DataInputStream.prototype, 'read_line_async');

export const RUNTIME = GLib.build_filenamev([GLib.get_user_runtime_dir(), 'kindle-reader']);
const SOCKET = GLib.build_filenamev([RUNTIME, 'control.sock']);

export class Bridge {
    constructor(dir) {
        this._script = dir.resolve_relative_path('backend/bridge.py').get_path();
        this._queue = Promise.resolve();
    }

    // One request at a time, in order (like the popup's queue): the reader answers each with
    // its full state. Resolves to that state; a failure resolves to {error}.
    request(payload) {
        const run = this._queue.then(() => this._run(payload));
        this._queue = run.catch(() => {});
        return run;
    }

    async _run(payload) {
        try {
            const proc = Gio.Subprocess.new(['python3', this._script],
                Gio.SubprocessFlags.STDIN_PIPE | Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
            const [out] = await proc.communicate_utf8_async(`${JSON.stringify(payload)}\n`, null);
            return JSON.parse(out.trim().split('\n').pop() || '{}');
        } catch (error) {
            return {error: error.message};
        }
    }
}

// The bar icon's light poll ({enabled, paused, status}) straight on the reader's socket, so
// nothing is started while the reader is off. Resolves to null when the reader does not run.
export async function watch() {
    if (!GLib.file_test(SOCKET, GLib.FileTest.EXISTS))
        return null;
    let connection = null;
    try {
        const client = new Gio.SocketClient({timeout: 2});
        connection = await client.connect_async(new Gio.UnixSocketAddress({path: SOCKET}), null);
        await connection.output_stream.write_all_async(
            new TextEncoder().encode(`${JSON.stringify({command: 'watch'})}\n`), GLib.PRIORITY_DEFAULT, null);
        const input = new Gio.DataInputStream({base_stream: connection.input_stream});
        const [line] = await input.read_line_async(GLib.PRIORITY_DEFAULT, null);
        return line ? JSON.parse(new TextDecoder().decode(line)) : null;
    } catch {
        return null;
    } finally {
        connection?.close_async(GLib.PRIORITY_DEFAULT, null).catch(() => {});
    }
}

// The first thing standing in the way of reading, as {text, label, payload}, or null.
// The setup steps are the ones the Omarchy popup offered as "Set up automatically".
export function nextStep(state) {
    const language = state.settings?.language ?? 'en';
    if (state.setup_busy)
        return {text: state.setup_message || 'Setting up…', label: state.setup_phase === 'packages' ? '' : 'Cancel',
            payload: {command: 'cancel-setup'}};
    if (state.backend_ready === false || state.missing_packages?.length) {
        const payload = {command: 'setup', language};
        if (['error', 'cancelled'].includes(state.setup_phase))
            return {text: state.setup_message, label: 'Retry setup', payload};
        const missing = state.missing_packages?.length ? ` It installs ${state.missing_packages.join(', ')}.` : '';
        return {text: `Screen Narrator needs its reader, a voice and text recognition.${missing}`,
            label: 'Set up automatically', payload};
    }
    const failed = (state.checks ?? []).find(check => !check.ok);
    if (!failed || state.enabled)
        return null;
    const fix = failed.fixes?.find(f => f.command || f.settings);
    if (!fix)
        return {text: failed.problem, label: 'Settings…', payload: null};
    const payload = fix.command ? {command: fix.command, ...fix.args} : {command: 'configure', settings: fix.settings};
    return {text: failed.problem, label: fix.label, payload};
}
