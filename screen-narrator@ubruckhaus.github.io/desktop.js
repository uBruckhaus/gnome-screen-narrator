// The desktop side of reading, for the reader's gnome_desktop.py: the focused window, a
// screenshot of an area or of the book window, an area the user drags, and page-turn keys.
// These stand in for hyprctl, grim, slurp and wtype on Omarchy.
//
// Screenshots and keys are only given while reading is on, only to the installed reader's
// helper, and a screenshot only goes into the reader's private runtime folder.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';

import {SelectArea} from 'resource:///org/gnome/shell/ui/screenshot.js';

import {RUNTIME, watch} from './bridge.js';

Gio._promisify(Gio.DBusConnection.prototype, 'call');
Gio._promisify(Shell.Screenshot.prototype, 'screenshot_area');
Gio._promisify(Shell.Screenshot, 'composite_to_stream');

const NAME = 'io.github.ubruckhaus.ScreenNarrator';
const PATH = '/io/github/ubruckhaus/ScreenNarrator';
const IFACE = `<node>
  <interface name="io.github.ubruckhaus.ScreenNarrator.Desktop">
    <method name="ActiveWindow"><arg type="s" direction="out"/></method>
    <method name="Window">
      <arg type="s" name="address" direction="in"/>
      <arg type="s" direction="out"/>
    </method>
    <method name="Clients"><arg type="s" direction="out"/></method>
    <method name="Capture">
      <arg type="s" name="geometry" direction="in"/>
      <arg type="s" name="path" direction="in"/>
      <arg type="b" direction="out"/>
    </method>
    <method name="CaptureWindow">
      <arg type="s" name="address" direction="in"/>
      <arg type="s" name="geometry" direction="in"/>
      <arg type="s" name="path" direction="in"/>
      <arg type="b" direction="out"/>
    </method>
    <method name="SelectArea"><arg type="s" direction="out"/></method>
    <method name="SendKey">
      <arg type="s" name="address" direction="in"/>
      <arg type="s" name="key" direction="in"/>
      <arg type="b" direction="out"/>
    </method>
    <method name="OpenSettings"/>
  </interface>
</node>`;
const CAPTURE_FILE = GLib.build_filenamev([RUNTIME, 'window.png']);
const HELPER = GLib.build_filenamev([GLib.get_user_data_dir(), 'kindle-reader/app/gnome_desktop.py']);
// How long a page-turn key may wait for the book window to take the focus it lends.
const FOCUS_WAIT = 300;

const sleep = ms => new Promise(resolve => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
    resolve();
    return GLib.SOURCE_REMOVE;
}));

export function address(window) {
    return `0x${window.get_id().toString(16)}`;
}

function describe(window) {
    const rect = window.get_frame_rect();
    return {
        address: address(window),
        pid: window.get_pid(),
        at: [rect.x, rect.y],
        size: [rect.width, rect.height],
        title: window.get_title() ?? '',
        class: window.get_wm_class() ?? window.get_gtk_application_id() ?? '',
        focused: window === global.display.focus_window,
        // On screen: an app on another workspace or minimized stops drawing, and keys
        // cannot reach it without switching there.
        shown: shown(window),
    };
}

function shown(window) {
    return !window.minimized && window.located_on_workspace(global.workspace_manager.get_active_workspace());
}

function findWindow(target) {
    return global.get_window_actors().map(actor => actor.meta_window)
        .find(window => address(window) === target) ?? null;
}

export class DesktopService {
    constructor(extension, highlight) {
        this._extension = extension;
        this._highlight = highlight;
        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbus.export(Gio.DBus.session, PATH);
        this._nameId = Gio.bus_own_name_on_connection(Gio.DBus.session, NAME,
            Gio.BusNameOwnerFlags.NONE, null, null);
        // Made up front: Mutter drops the keys of a virtual keyboard created right before
        // them, which lost the first page turn after every shell start.
        this._keyboard = global.stage.context.get_backend().get_default_seat()
            .create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);
        this._selector = null;
    }

    destroy() {
        this._selector?._grabHelper.ungrab();
        Gio.bus_unown_name(this._nameId);
        this._dbus.unexport();
        this._keyboard?.run_dispose();
        this._keyboard = null;
    }

    ActiveWindow() {
        const window = global.display.focus_window;
        return JSON.stringify(window ? describe(window) : {});
    }

    // The book window the reader pinned, wherever the focus is; {} once it is closed.
    Window(target) {
        const window = findWindow(target);
        return JSON.stringify(window ? describe(window) : {});
    }

    Clients() {
        return JSON.stringify(global.get_window_actors()
            .map(actor => actor.meta_window)
            .filter(window => window.get_window_type() === Meta.WindowType.NORMAL)
            .map(describe));
    }

    async CaptureAsync([geometry, path], invocation) {
        try {
            const match = /^(-?\d+),(-?\d+) (\d+)x(\d+)$/.exec(geometry);
            if (!match || path !== CAPTURE_FILE)
                throw new Error(`not the reader's capture: ${geometry} ${path}`);
            if (!await this._reading())
                throw new Error('reading is off');
            if (!await this._fromReader(invocation))
                throw new Error('not asked by the installed reader');
            const [x, y, width, height] = match.slice(1).map(Number);
            const file = Gio.File.new_for_path(path);
            const stream = file.replace(null, false, Gio.FileCreateFlags.PRIVATE | Gio.FileCreateFlags.REPLACE_DESTINATION, null);
            // The passage boxes are drawn over the page: they must not end up in the text.
            this._highlight.hidden = true;
            try {
                await new Shell.Screenshot().screenshot_area(x, y, width, height, stream);
            } finally {
                this._highlight.hidden = false;
                stream.close(null);
            }
            invocation.return_value(new GLib.Variant('(b)', [true]));
        } catch (error) {
            console.warn(`[Screen Narrator] capture refused or failed: ${error.message}`);
            invocation.return_value(new GLib.Variant('(b)', [false]));
        }
    }

    // Part of one window ("X,Y WxH" on the screen, inside that window), from the window's own
    // picture: windows over it or the focus elsewhere do not matter.
    async CaptureWindowAsync([target, geometry, path], invocation) {
        try {
            const match = /^(-?\d+),(-?\d+) (\d+)x(\d+)$/.exec(geometry);
            if (!match || path !== CAPTURE_FILE)
                throw new Error(`not the reader's capture: ${geometry} ${path}`);
            if (!await this._reading())
                throw new Error('reading is off');
            if (!await this._fromReader(invocation))
                throw new Error('not asked by the installed reader');
            const window = findWindow(target);
            const actor = window?.get_compositor_private();
            if (!actor || !shown(window))
                throw new Error(`window ${target} is not on screen`);
            const texture = actor.paint_to_content(null)?.get_texture();
            if (!texture)
                throw new Error(`window ${target} has nothing to show`);
            // The picture covers the window's buffer (shadows included), at its own scale.
            const buffer = window.get_buffer_rect();
            const scale = texture.get_width() / Math.max(1, buffer.width);
            const [x, y, width, height] = match.slice(1).map(Number);
            const left = Math.max(0, Math.round((x - buffer.x) * scale));
            const top = Math.max(0, Math.round((y - buffer.y) * scale));
            const right = Math.min(texture.get_width(), Math.round((x + width - buffer.x) * scale));
            const bottom = Math.min(texture.get_height(), Math.round((y + height - buffer.y) * scale));
            if (right - left < 1 || bottom - top < 1)
                throw new Error(`${geometry} is outside window ${target}`);
            const stream = Gio.File.new_for_path(path).replace(null, false,
                Gio.FileCreateFlags.PRIVATE | Gio.FileCreateFlags.REPLACE_DESTINATION, null);
            try {
                await Shell.Screenshot.composite_to_stream(texture, left, top, right - left, bottom - top,
                    1, null, 0, 0, 1, stream);
            } finally {
                stream.close(null);
            }
            invocation.return_value(new GLib.Variant('(b)', [true]));
        } catch (error) {
            console.warn(`[Screen Narrator] window capture refused or failed: ${error.message}`);
            invocation.return_value(new GLib.Variant('(b)', [false]));
        }
    }

    // "X,Y WxH" like slurp, or "" when cancelled.
    async SelectAreaAsync(_params, invocation) {
        if (!await this._fromReader(invocation)) {
            invocation.return_value(new GLib.Variant('(s)', ['']));
            return;
        }
        // GNOME's own area picker (the screenshot tool's): drag a box, Esc cancels.
        this._selector?._grabHelper.ungrab();
        const selector = this._selector = new SelectArea();
        const area = await selector.selectAsync().catch(() => null);
        if (this._selector === selector)
            this._selector = null;
        invocation.return_value(new GLib.Variant('(s)',
            [area ? `${area.x},${area.y} ${area.width}x${area.height}` : '']));
    }

    // key: an X keysym name ("Right", "n", "Next") for the book window. Keys only go to the
    // focused window, so a book in the background gets the focus for a moment, without being
    // raised, and the window that had it gets it back. Not for a book on another workspace or
    // minimized: that would switch workspaces or show it.
    async SendKeyAsync([target, key], invocation) {
        const keyval = Clutter[`KEY_${key}`];
        let ok = Boolean(keyval && await this._reading() && await this._fromReader(invocation));
        const window = ok ? findWindow(target) : null;
        ok = Boolean(window && shown(window));
        if (ok) {
            const previous = global.display.focus_window;
            const workspace = global.workspace_manager.get_active_workspace();
            const lent = previous !== window;
            if (lent) {
                this._highlight.hidden = true;
                window.focus(global.get_current_time());
                for (let waited = 0; global.display.focus_window !== window && waited < FOCUS_WAIT; waited += 20)
                    await sleep(20);
                ok = global.display.focus_window === window;
            }
            // The waits let reading stop, the book leave the screen or the focus move meanwhile:
            // the focus is checked last, right before the key.
            ok &&= shown(window) && await this._reading() && global.display.focus_window === window;
            if (ok) {
                const time = GLib.get_monotonic_time();
                this._keyboard.notify_keyval(time, keyval, Clutter.KeyState.PRESSED);
                this._keyboard.notify_keyval(time + 1000, keyval, Clutter.KeyState.RELEASED);
            }
            if (lent) {
                // Let the key reach the book before the focus goes back, and only give it back
                // if nothing else took the focus meanwhile (the user clicking somewhere) and the
                // user is still on the same workspace, where that window still is.
                await sleep(80);
                if (global.display.focus_window === window && previous && findWindow(address(previous)) &&
                    global.workspace_manager.get_active_workspace() === workspace &&
                    previous.located_on_workspace(workspace) && !previous.minimized)
                    previous.focus(global.get_current_time());
                this._highlight.hidden = false;
            }
        }
        invocation.return_value(new GLib.Variant('(b)', [ok]));
    }

    OpenSettings() {
        this._extension.openPreferences();
    }

    async _reading() {
        return (await watch())?.enabled === true;
    }

    // The caller is the installed reader's helper (gnome_desktop.py) of this user.
    async _fromReader(invocation) {
        try {
            const reply = await Gio.DBus.session.call('org.freedesktop.DBus', '/org/freedesktop/DBus',
                'org.freedesktop.DBus', 'GetConnectionUnixProcessID',
                new GLib.Variant('(s)', [invocation.get_sender()]), new GLib.VariantType('(u)'),
                Gio.DBusCallFlags.NONE, -1, null);
            // The helper calls through busctl: the caller is busctl, its parent the helper.
            const [pid] = reply.deepUnpack();
            const read = file => new TextDecoder().decode(GLib.file_get_contents(`/proc/${pid}/${file}`)[1]);
            const ppid = Number(/^PPid:\s*(\d+)/m.exec(read('status'))?.[1]);
            const [, parent] = GLib.file_get_contents(`/proc/${ppid}/cmdline`);
            return read('cmdline').split('\0')[0].endsWith('busctl') &&
                new TextDecoder().decode(parent).split('\0').includes(HELPER);
        } catch {
            return false;
        }
    }
}
