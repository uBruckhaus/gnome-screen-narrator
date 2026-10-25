// The desktop side of reading, for the reader's gnome_desktop.py: the focused window, a
// screenshot of an area, an area the user drags, and page-turn keys. These stand in for
// hyprctl, grim, slurp and wtype on Omarchy.
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

const NAME = 'io.github.ubruckhaus.ScreenNarrator';
const PATH = '/io/github/ubruckhaus/ScreenNarrator';
const IFACE = `<node>
  <interface name="io.github.ubruckhaus.ScreenNarrator.Desktop">
    <method name="ActiveWindow"><arg type="s" direction="out"/></method>
    <method name="Clients"><arg type="s" direction="out"/></method>
    <method name="Capture">
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
    };
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

    // key: an X keysym name ("Right", "n", "Next"), sent only to the focused reading window.
    async SendKeyAsync([target, key], invocation) {
        const window = global.display.focus_window;
        const keyval = Clutter[`KEY_${key}`];
        const ok = Boolean(window && address(window) === target && keyval && await this._reading() &&
            await this._fromReader(invocation));
        if (ok) {
            const time = GLib.get_monotonic_time();
            this._keyboard.notify_keyval(time, keyval, Clutter.KeyState.PRESSED);
            this._keyboard.notify_keyval(time + 1000, keyval, Clutter.KeyState.RELEASED);
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
