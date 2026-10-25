// The headphones button in the top bar. Left click opens the menu (Start / Pause / Stop,
// what needs setting up, reading area, speed, settings); right click starts or stops
// reading, middle click pauses. The icon turns green while reading.

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Slider} from 'resource:///org/gnome/shell/ui/slider.js';

import {Bridge, nextStep, watch} from './bridge.js';

const MIN_SPEED = 0.6;
const MAX_SPEED = 2;

export const Indicator = GObject.registerClass(
class ScreenNarratorIndicator extends PanelMenu.Button {
    _init(extension) {
        super._init(0.5, 'Screen Narrator');
        this._extension = extension;
        this._bridge = new Bridge(extension.dir);
        this._state = {};
        this._reading = false;

        this._icon = new St.Icon({icon_name: 'audio-headphones-symbolic', style_class: 'system-status-icon'});
        this.add_child(this._icon);

        // Left click opens the menu; right click starts or stops, middle click pauses.
        this._clickGesture?.set_required_button?.(Clutter.BUTTON_PRIMARY);
        const toggleGesture = new Clutter.ClickGesture({
            required_button: Clutter.BUTTON_SECONDARY,
            recognize_on_press: true,
        });
        toggleGesture.connect('recognize', () => this._send({command: 'toggle'}));
        this.add_action(toggleGesture);
        const pauseGesture = new Clutter.ClickGesture({
            required_button: Clutter.BUTTON_MIDDLE,
            recognize_on_press: true,
        });
        pauseGesture.connect('recognize', () => this._send({command: 'pause'}));
        this.add_action(pauseGesture);

        this._buildMenu();
        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this._refresh();
        });

        // Light poll for the icon; while the menu is open the full state is fetched instead.
        this._pollId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
            this._poll();
            return GLib.SOURCE_CONTINUE;
        });
        this._poll();
    }

    destroy() {
        GLib.source_remove(this._pollId);
        if (this._speedId)
            GLib.source_remove(this._speedId);
        super.destroy();
    }

    _buildMenu() {
        this._statusItem = new PopupMenu.PopupMenuItem('Screen Narrator', {reactive: false});
        this._statusItem.label.add_style_class_name('screen-narrator-status');
        this.menu.addMenuItem(this._statusItem);

        const controls = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        const row = new St.BoxLayout({style_class: 'screen-narrator-controls', x_expand: true});
        const button = (icon, label, payload) => {
            const box = new St.BoxLayout({x_align: Clutter.ActorAlign.CENTER, style_class: 'screen-narrator-button-box'});
            box.add_child(new St.Icon({icon_name: icon, icon_size: 16}));
            box.add_child(new St.Label({text: label, y_align: Clutter.ActorAlign.CENTER}));
            const b = new St.Button({style_class: 'screen-narrator-button', can_focus: true, x_expand: true, child: box});
            b.connect('clicked', () => this._send(payload));
            row.add_child(b);
            return b;
        };
        this._startButton = button('media-playback-start-symbolic', 'Start', {command: 'on'});
        this._pauseButton = button('media-playback-pause-symbolic', 'Pause', {command: 'pause'});
        this._stopButton = button('media-playback-stop-symbolic', 'Stop', {command: 'off'});
        controls.add_child(row);
        this.menu.addMenuItem(controls);

        // What has to happen before reading can start, with the one button that does it.
        this._stepItem = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        const stepBox = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true,
            style_class: 'screen-narrator-step'});
        this._stepLabel = new St.Label({style_class: 'screen-narrator-step-text'});
        this._stepLabel.clutter_text.line_wrap = true;
        this._stepButton = new St.Button({style_class: 'screen-narrator-button screen-narrator-step-button', can_focus: true});
        this._stepButton.connect('clicked', () => {
            const step = this._step;
            if (step?.payload)
                this._send(step.payload);
            else
                this._openSettings();
        });
        stepBox.add_child(this._stepLabel);
        stepBox.add_child(this._stepButton);
        this._stepItem.add_child(stepBox);
        this.menu.addMenuItem(this._stepItem);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this._againItem = this.menu.addAction('Read again', () => this._send({command: 'read'}));
        this._areaItem = this.menu.addAction('Select reading area…', () => this._send({command: 'select-area'}));
        this._clearAreaItem = this.menu.addAction('Reset reading area', () => this._send({command: 'clear-area'}));

        const speedItem = new PopupMenu.PopupBaseMenuItem({activate: false});
        this._speedLabel = new St.Label({text: 'Speed', style_class: 'screen-narrator-speed', y_align: Clutter.ActorAlign.CENTER});
        this._slider = new Slider(0);
        this._slider.x_expand = true;
        this._slider.accessible_name = 'Reading speed';
        this._dragging = false;
        this._speedId = 0;
        this._slider.connect('notify::value', () => {
            this._speedLabel.text = `${this._speed().toFixed(2)}×`;
            if (this._syncing)
                return;
            // Dragged, scrolled or moved with the arrow keys: saved once it rests.
            if (this._speedId)
                GLib.source_remove(this._speedId);
            this._speedId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 400, () => {
                this._speedId = 0;
                if (!this._dragging)
                    this._send({command: 'configure', settings: {speed: this._speed()}});
                return GLib.SOURCE_REMOVE;
            });
        });
        this._slider.connect('drag-begin', () => {
            this._dragging = true;
        });
        this._slider.connect('drag-end', () => {
            this._dragging = false;
            this._send({command: 'configure', settings: {speed: this._speed()}});
        });
        speedItem.add_child(new St.Icon({icon_name: 'media-seek-forward-symbolic', style_class: 'popup-menu-icon'}));
        speedItem.add_child(this._slider);
        speedItem.add_child(this._speedLabel);
        this._speedItem = speedItem;
        this.menu.addMenuItem(speedItem);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        this.menu.addAction('Settings…', () => this._openSettings());
        this._sync();
    }

    _speed() {
        return Math.round((MIN_SPEED + this._slider.value * (MAX_SPEED - MIN_SPEED)) * 20) / 20;
    }

    _openSettings() {
        this.menu.close();
        this._extension.openPreferences();
    }

    async _poll() {
        if (this.menu.isOpen) {
            await this._refresh();
            return;
        }
        const state = await watch();
        this._setReading(state);
    }

    async _refresh() {
        this._update(await this._bridge.request({command: 'status'}));
    }

    async _send(payload) {
        if (payload.command === 'select-area')
            this.menu.close();
        const state = await this._bridge.request(payload);
        if (state.error)
            Main.notify('Screen Narrator', state.error);
        this._update(state);
    }

    _update(state) {
        if (state.error)
            return;
        this._state = state;
        this._setReading(state);
        this._sync();
    }

    _setReading(state) {
        this._reading = Boolean(state?.enabled);
        this._paused = Boolean(state?.paused);
        if (this._reading && !this._paused)
            this._icon.add_style_class_name('screen-narrator-reading');
        else
            this._icon.remove_style_class_name('screen-narrator-reading');
        if (this._paused)
            this._icon.add_style_class_name('screen-narrator-paused');
        else
            this._icon.remove_style_class_name('screen-narrator-paused');
    }

    _sync() {
        const state = this._state;
        const ready = state.backend_ready === true && !state.setup_busy;
        const window = state.window && state.enabled ? ` · ${state.window}` : '';
        this._statusItem.label.text = `${state.status ?? 'Screen Narrator'}${window}`;

        this._startButton.reactive = ready && !this._reading && state.can_start !== false;
        this._pauseButton.reactive = this._reading;
        this._stopButton.reactive = this._reading;
        this._pauseButton.child.get_child_at_index(1).text = this._paused ? 'Resume' : 'Pause';
        this._pauseButton.child.get_child_at_index(0).icon_name =
            this._paused ? 'media-playback-start-symbolic' : 'media-playback-pause-symbolic';

        this._step = state.status === undefined ? null : nextStep(state);
        this._stepItem.visible = Boolean(this._step);
        if (this._step) {
            this._stepLabel.text = this._step.text;
            this._stepButton.label = this._step.label;
            this._stepButton.visible = Boolean(this._step.label);
        }

        this._againItem.setSensitive(this._reading);
        this._areaItem.setSensitive(ready);
        this._clearAreaItem.visible = Boolean(state.custom_area || state.settings?.kindle_area);
        this._speedItem.visible = ready;
        const speed = Number(state.settings?.speed ?? 1);
        if (!this._dragging && !this._speedId) {
            this._syncing = true;
            this._slider.value = (speed - MIN_SPEED) / (MAX_SPEED - MIN_SPEED);
            this._syncing = false;
            this._speedLabel.text = `${speed.toFixed(2)}×`;
        }
    }
});
