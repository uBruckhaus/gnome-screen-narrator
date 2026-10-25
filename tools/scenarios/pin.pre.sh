# Test-only hook in the throwaway copy: lets the scenario move and minimize windows.
cat >> "$EXT/extension.js" <<'JS'
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
const TEST_IFACE = `<node><interface name="io.github.ubruckhaus.ScreenNarrator.Test">
<method name="Do"><arg type="s" direction="in"/><arg type="s" direction="in"/></method>
</interface></node>`;
const _enable = ScreenNarratorExtension.prototype.enable;
ScreenNarratorExtension.prototype.enable = function () {
    _enable.call(this);
    const find = title => global.get_window_actors().map(a => a.meta_window).find(w => (w.get_title() ?? '').startsWith(title));
    const test = Gio.DBusExportedObject.wrapJSObject(TEST_IFACE, {
        Do(action, title) {
            const window = find(title);
            if (action === 'workspace2') window.change_workspace_by_index(1, false);
            if (action === 'workspace1') window.change_workspace_by_index(0, false);
            if (action === 'minimize') window.minimize();
            if (action === 'unminimize') window.unminimize();
            if (action === 'cover') { window.move_resize_frame(false, 0, 0, 1920, 1080); }
        },
    });
    this._test = test;
    test.export(Gio.DBus.session, '/test');
};
JS
