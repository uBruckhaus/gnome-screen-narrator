# Test-only patch of the copied extension: open the menu, screenshot it, then the settings window.
cat >> "$EXT/extension.js" <<'JS'
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
const shot = (name, done) => {
    const stream = Gio.File.new_for_path(`${GLib.getenv('SN_SHOTS')}/${name}.png`).replace(null, false, 0, null);
    new Shell.Screenshot().screenshot(false, stream, (s, res) => {
        s.screenshot_finish(res); stream.close(null); console.log(`[Screen Narrator] screenshot ${name}`); done?.();
    });
};
const _origEnable = ScreenNarratorExtension.prototype.enable;
ScreenNarratorExtension.prototype.enable = function () {
    _origEnable.call(this);
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 9000, () => {
        Main.overview.hide();
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
            this._indicator.menu.open(false);
            return GLib.SOURCE_REMOVE;
        });
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 4000, () => {
            shot('menu', () => {
                this._indicator.menu.close(false);
                this.openPreferences();
                GLib.timeout_add(GLib.PRIORITY_DEFAULT, 6000, () => { shot('prefs'); return GLib.SOURCE_REMOVE; });
            });
            return GLib.SOURCE_REMOVE;
        });
        return GLib.SOURCE_REMOVE;
    });
};
JS
export SN_SHOTS="$ROOT/dist/screenshots"; mkdir -p "$SN_SHOTS"
