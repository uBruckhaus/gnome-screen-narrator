# Test-only patch: focus the first app window, as a user would before pressing Start.
cat >> "$EXT/extension.js" <<'JS'
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
const _origEnable = ScreenNarratorExtension.prototype.enable;
ScreenNarratorExtension.prototype.enable = function () {
    _origEnable.call(this);
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
        Main.overview.hide();
        const window = global.get_window_actors().map(a => a.meta_window).find(w => w.get_wm_class());
        window?.activate(global.get_current_time());
        return GLib.SOURCE_CONTINUE;
    });
    // The whole screen once the scenario has written passage boxes (highlight.png).
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 13500, () => {
        const stream = Gio.File.new_for_path(`${GLib.getenv('SN_SHOTS')}/highlight.png`).replace(null, false, 0, null);
        new Shell.Screenshot().screenshot(false, stream, (sc, res) => { sc.screenshot_finish(res); stream.close(null); });
        return GLib.SOURCE_REMOVE;
    });
};
JS
export SN_SHOTS="$ROOT/dist/screenshots"; mkdir -p "$SN_SHOTS"
