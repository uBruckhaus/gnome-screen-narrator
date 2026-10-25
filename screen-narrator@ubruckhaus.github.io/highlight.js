// The passage being read, as boxes over the reading window. The reader writes them to
// highlight.json in its runtime folder ({rectangles: [{x, y, width, height}], target});
// they show while that window has focus (highlight.qml on Omarchy).

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {RUNTIME} from './bridge.js';
import {address} from './desktop.js';

const FILE = 'highlight.json';

export class Highlight {
    constructor() {
        this._rectangles = [];
        this._target = '';
        this._hidden = false;
        this._layer = new St.Widget({reactive: false});
        // Over the windows, under the top bar and its menus.
        Main.layoutManager.uiGroup.insert_child_above(this._layer, global.window_group);
        this._focusId = global.display.connect('notify::focus-window', () => this._sync());
        this._monitor = null;
        this._retryId = 0;
        this._watch();
    }

    destroy() {
        if (this._retryId)
            GLib.source_remove(this._retryId);
        this._monitor?.cancel();
        global.display.disconnect(this._focusId);
        this._layer.destroy();
    }

    // Hidden while a screenshot for the text is taken.
    set hidden(hidden) {
        this._hidden = hidden;
        this._sync();
    }

    _watch() {
        // The runtime folder exists once the reader has run; until then look again now and then.
        const folder = Gio.File.new_for_path(RUNTIME);
        if (!folder.query_exists(null)) {
            this._retryId = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, 5, () => {
                this._retryId = 0;
                this._watch();
                return GLib.SOURCE_REMOVE;
            });
            return;
        }
        // The reader replaces the file (write and rename), so the folder is watched.
        this._monitor = folder.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._monitor.connect('changed', (_monitor, file, other) => {
            if (file.get_basename() === FILE || other?.get_basename() === FILE)
                this._load();
        });
        this._load();
    }

    _load() {
        try {
            const [, bytes] = GLib.file_get_contents(GLib.build_filenamev([RUNTIME, FILE]));
            const state = JSON.parse(new TextDecoder().decode(bytes));
            this._rectangles = Array.isArray(state.rectangles) ? state.rectangles : [];
            this._target = String(state.target ?? '');
        } catch {
            this._rectangles = [];
        }
        this._draw();
    }

    _draw() {
        this._layer.destroy_all_children();
        for (const r of this._rectangles) {
            if (![r.x, r.y, r.width, r.height].every(Number.isFinite))
                continue;
            this._layer.add_child(new St.Widget({
                style_class: 'screen-narrator-highlight',
                x: Math.round(r.x) - 2,
                y: Math.round(r.y) - 2,
                width: Math.round(r.width) + 4,
                height: Math.round(r.height) + 4,
            }));
        }
        this._sync();
    }

    _sync() {
        const window = global.display.focus_window;
        const focused = window && address(window).replace(/^0x/, '') === this._target;
        this._layer.visible = !this._hidden && this._rectangles.length > 0 && Boolean(focused);
    }
}
