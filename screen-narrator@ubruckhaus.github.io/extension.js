import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {DesktopService} from './desktop.js';
import {Highlight} from './highlight.js';
import {Indicator} from './indicator.js';

// The reader itself is a user service (ocrvox.service, set up from the menu); this is its
// bar icon and its desktop side. Disabling the extension leaves the service as it is.
export default class ScreenNarratorExtension extends Extension {
    enable() {
        this._highlight = new Highlight();
        this._desktop = new DesktopService(this, this._highlight);
        this._indicator = new Indicator(this);
        Main.panel.addToStatusArea(this.uuid, this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
        this._desktop?.destroy();
        this._desktop = null;
        this._highlight?.destroy();
        this._highlight = null;
    }
}
