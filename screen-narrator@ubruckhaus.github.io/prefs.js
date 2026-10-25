// The settings window: what needs setting up, then Reading, Voice and Translation (the
// groups of the Omarchy popup). Every change goes to the reader at once through the bridge.

import Adw from 'gi://Adw';
import GLib from 'gi://GLib';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

import {Bridge, nextStep} from './bridge.js';

const SERVERS = [
    ['llama.cpp', 'http://127.0.0.1:8080/v1'],
    ['LM Studio', 'http://127.0.0.1:1234/v1'],
    ['Ollama', 'http://127.0.0.1:11434/v1'],
];
const OFFLINE = 'Offline translator (NLLB-200)';

// A combo row over (value, label) choices that can change while the window is open.
class Choice {
    constructor(props, onPick) {
        this.row = new Adw.ComboRow({...props, model: new Gtk.StringList()});
        this._values = [];
        this._signature = '';
        this._syncing = false;
        if (props.enable_search)
            this.row.expression = new Gtk.PropertyExpression(Gtk.StringObject, null, 'string');
        this.row.connect('notify::selected', () => {
            const value = this._values[this.row.selected];
            if (!this._syncing && value !== undefined && value !== this._value)
                onPick(value);
        });
    }

    set(choices, value) {
        this._syncing = true;
        const signature = JSON.stringify(choices);
        if (signature !== this._signature) {
            this._signature = signature;
            this._values = choices.map(([v]) => v);
            this.row.model = Gtk.StringList.new(choices.map(([, label]) => label));
        }
        this._value = value;
        const index = this._values.indexOf(value);
        this.row.selected = index < 0 ? Gtk.INVALID_LIST_POSITION : index;
        this._syncing = false;
    }
}

function button(label, onClick, css = []) {
    const b = new Gtk.Button({label, valign: Gtk.Align.CENTER, css_classes: css});
    b.connect('clicked', onClick);
    return b;
}

export default class ScreenNarratorPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        this._window = window;
        this._bridge = new Bridge(this.dir);
        this._state = {};
        window.set_default_size(640, 820);
        window.set_search_enabled(false);

        const page = new Adw.PreferencesPage({title: 'Screen Narrator', icon_name: 'audio-headphones-symbolic'});
        window.add(page);
        page.add(this._statusGroup());
        page.add(this._readingGroup());
        page.add(this._voiceGroup());
        page.add(this._serverGroup());
        page.add(this._translationGroup());

        this._refresh();
        const timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1500, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
        window.connect('close-request', () => {
            GLib.source_remove(timer);
            return false;
        });
    }

    async _send(payload) {
        const state = await this._bridge.request(payload);
        if (state.error)
            this._window.add_toast(new Adw.Toast({title: state.error, timeout: 6}));
        else
            this._update(state);
    }

    _configure(settings) {
        this._send({command: 'configure', settings});
    }

    async _refresh() {
        const state = await this._bridge.request({command: 'status'});
        if (!state.error)
            this._update(state);
    }

    _statusGroup() {
        const group = new Adw.PreferencesGroup();
        this._statusRow = new Adw.ActionRow({title: 'Screen Narrator', subtitle_lines: 0});
        this._stepButton = button('', () => {
            if (this._step?.payload)
                this._send(this._step.payload);
        }, ['suggested-action']);
        this._statusRow.add_suffix(this._stepButton);
        group.add(this._statusRow);
        this._noticeRow = new Adw.ActionRow({title: 'Last problem', subtitle_lines: 0, visible: false});
        this._noticeRow.add_css_class('error');
        group.add(this._noticeRow);
        return group;
    }

    _readingGroup() {
        const group = new Adw.PreferencesGroup({title: 'Reading'});
        this._language = new Choice({title: 'Text language', subtitle: 'The language of the text on screen',
            enable_search: true}, language => this._configure({language}));
        group.add(this._language.row);

        this._speed = new Adw.SpinRow({
            title: 'Reading speed',
            digits: 2,
            adjustment: new Gtk.Adjustment({lower: 0.6, upper: 2, step_increment: 0.05, page_increment: 0.25}),
        });
        this._speed.connect('notify::value', () => {
            if (!this._syncing)
                this._configure({speed: Math.round(this._speed.value * 100) / 100});
        });
        group.add(this._speed);

        this._switches = {};
        for (const [key, title, subtitle] of [
            ['follow', 'Follow the active window', 'Read the window that has focus, and new pages as they appear'],
            ['highlight', 'Highlight the passage being read', ''],
            ['pdf_page_area', 'Read only the page in PDF viewers', 'Document Viewer and Papers: no toolbar, sidebar or page numbers'],
            ['kindle_crop', 'Skip the Kindle toolbar and progress bar', ''],
            ['auto_page_turn', 'Turn Kindle and PDF pages after reading', 'Stops at the end of the document'],
        ]) {
            const row = new Adw.SwitchRow({title, subtitle});
            row.connect('notify::active', () => {
                if (!this._syncing)
                    this._configure({[key]: row.active});
            });
            this._switches[key] = row;
            group.add(row);
        }

        this._areaRow = new Adw.ActionRow({title: 'Reading area'});
        this._areaReset = button('Reset', () => this._send({command: 'clear-area'}), ['flat']);
        this._areaRow.add_suffix(this._areaReset);
        this._areaRow.add_suffix(button('Select…', () => this._send({command: 'select-area'})));
        group.add(this._areaRow);
        return group;
    }

    _voiceGroup() {
        const group = new Adw.PreferencesGroup({title: 'Voice'});
        this._voice = new Choice({title: 'Voice'}, voice => this._configure({provider: 'Local', voice}));
        this._voice.row.add_suffix(button('Test', () => this._send({command: 'test-voice'}), ['flat']));
        group.add(this._voice.row);
        this._output = new Choice({title: 'Audio output'}, value => this._configure({audio_output: value}));
        group.add(this._output.row);

        // Kokoro (or Piper where Kokoro has no voice) for any language, with its text recognition.
        this._install = new Choice({title: 'Install a voice', subtitle: 'With text recognition for the language',
            enable_search: true}, value => {
            this._installLanguage = value;
        });
        this._install.row.add_suffix(button('Install', () => {
            const language = this._installLanguage ?? this._state.settings?.language;
            if (language)
                this._send({command: 'setup', language});
        }));
        group.add(this._install.row);
        return group;
    }

    // An OpenAI-compatible speech server instead of the voices on this computer. Like on
    // Omarchy it is tested first (a sample sentence through the audio output), then used.
    _serverGroup() {
        const group = new Adw.PreferencesGroup({title: 'Speech server',
            description: 'An OpenAI-compatible server with /v1/audio/speech and WAV output. A remote server ' +
                'receives the text being read and may charge for speech; a server on this computer keeps it here.'});
        this._serverActive = new Adw.ActionRow({title: 'In use', subtitle_lines: 0});
        this._localButton = button('Use voices on this computer', () => this._configure({provider: 'Local'}));
        this._serverActive.add_suffix(this._localButton);
        group.add(this._serverActive);

        this._endpointRow = new Adw.EntryRow({title: 'Server address (https://…/v1, or http://localhost)'});
        group.add(this._endpointRow);
        this._modelRow = new Adw.EntryRow({title: 'Speech model'});
        this._modelRow.add_suffix(button('Find models', () => this._send({
            command: 'online-models', endpoint: this._endpointRow.text.trim(), token: this._tokenRow.text || null,
        }), ['flat']));
        group.add(this._modelRow);
        this._found = new Choice({title: 'Models on the server', subtitle: 'Chat models cannot speak: choose a speech model',
            enable_search: true}, model => {
            this._modelRow.text = model;
        });
        group.add(this._found.row);
        this._voiceIdRow = new Adw.EntryRow({title: 'Voice'});
        group.add(this._voiceIdRow);
        this._tokenRow = new Adw.PasswordEntryRow({title: 'API key / token, if the server needs one'});
        group.add(this._tokenRow);
        this._rememberRow = new Adw.SwitchRow({title: 'Remember the token on this device',
            subtitle: 'Saved in an owner-only plain-text file'});
        group.add(this._rememberRow);

        this._serverTest = new Adw.ActionRow({title: 'Test the voice, then use the server', subtitle_lines: 0});
        this._serverTest.add_suffix(button('Test', () => {
            this._testedToken = this._tokenRow.text;
            this._send({command: 'test-provider', settings: this._candidate(), token: this._tokenRow.text || null});
        }));
        this._useButton = button('Use', () => this._send({
            command: 'use-provider', settings: this._candidate(), token: this._tokenRow.text || null,
            remember_token: this._rememberRow.active,
        }), ['suggested-action']);
        this._serverTest.add_suffix(this._useButton);
        group.add(this._serverTest);

        this._clearToken = new Adw.ActionRow({title: 'Saved token of the server in use'});
        this._clearToken.add_suffix(button('Clear', () => this._send({command: 'configure-token', token: '', remember_token: false}), ['flat']));
        group.add(this._clearToken);

        for (const row of [this._endpointRow, this._modelRow, this._voiceIdRow, this._tokenRow])
            row.connect('changed', () => this._syncServer());
        return group;
    }

    _candidate() {
        return {
            provider: 'Online',
            online_endpoint: this._endpointRow.text.trim(),
            online_model: this._modelRow.text.trim(),
            online_voice: this._voiceIdRow.text.trim(),
        };
    }

    // Use only what was tested: the same server, model, voice and token.
    _syncServer() {
        const candidate = this._candidate();
        const verified = this._state.verified_provider ?? {};
        const ready = Boolean(candidate.online_endpoint && candidate.online_model && candidate.online_voice);
        this._useButton.sensitive = ready && this._tokenRow.text === (this._testedToken ?? '') &&
            Object.entries(candidate).every(([key, value]) => verified[key] === value);
    }

    _translationGroup() {
        const group = new Adw.PreferencesGroup({title: 'Translation',
            description: 'Read the text in one language and hear it in another'});
        this._speakIn = new Choice({title: 'Speak in', enable_search: true}, value => this._configure({translate_to: value}));
        group.add(this._speakIn.row);

        this._translator = new Choice({title: 'Translator'}, value => {
            if (value === 'nllb')
                this._configure({translator: 'nllb'});
            else
                this._configure({translator: 'llm', translator_endpoint: value, translator_model: ''});
        });
        group.add(this._translator.row);

        this._model = new Choice({title: 'Model', subtitle: 'A chat or instruct model of the server'},
            value => this._configure({translator_model: value}));
        this._model.row.add_suffix(button('Refresh', () => this._send({command: 'translator-models'}), ['flat']));
        group.add(this._model.row);

        this._offlineRow = new Adw.ActionRow({title: 'Offline translator',
            subtitle: 'NLLB-200 1.3B, about 1.4 GB, non-commercial use only (CC-BY-NC 4.0)'});
        this._offlineButton = button('Install', () => this._send({
            command: this._state.installing_translator ? 'cancel-translator-install' : 'install-translator',
        }));
        this._offlineRow.add_suffix(this._offlineButton);
        group.add(this._offlineRow);

        this._testRow = new Adw.ActionRow({title: 'Test translation', subtitle_lines: 0});
        this._testRow.add_suffix(button('Test', () => this._send({command: 'test-translation'})));
        group.add(this._testRow);
        return group;
    }

    _update(state) {
        this._state = state;
        const settings = state.settings ?? {};
        const ready = state.backend_ready === true && !state.setup_busy;
        const languages = (state.languages ?? []).map(o => [o.value, o.label]);
        this._syncing = true;

        this._statusRow.title = state.status ?? 'Screen Narrator';
        this._step = nextStep(state);
        this._statusRow.subtitle = this._step?.text ?? (state.window ? `Reading: ${state.window}` : '');
        this._stepButton.visible = Boolean(this._step?.label && this._step.payload);
        this._stepButton.label = this._step?.label ?? '';
        const notice = (state.notices ?? []).at(-1);
        this._noticeRow.visible = Boolean(notice);
        this._noticeRow.subtitle = notice ? `${notice.title}: ${notice.text}` : '';

        this._language.set(languages, settings.language);
        this._speed.value = Number(settings.speed ?? 1);
        for (const [key, row] of Object.entries(this._switches))
            row.active = settings[key] ?? true;
        const kindle = settings.kindle_area;
        this._areaRow.subtitle = state.custom_area
            ? `Selected area (${state.custom_area[2]}×${state.custom_area[3]} px)`
            : kindle ? `Kindle (${Math.round(kindle[2] * 100)}% × ${Math.round(kindle[3] * 100)}%)` : 'The whole active window';
        this._areaReset.visible = Boolean(state.custom_area || kindle);

        const online = settings.provider === 'Online';
        const voices = (state.voices ?? []).map(v => [v.value, v.label]);
        this._voice.set(voices, online ? null : settings.voice);
        this._voice.row.subtitle = online ? 'A speech server is in use; choosing a voice here switches back'
            : voices.length ? '' : 'No voice is installed for this language yet';
        this._output.set((state.audio_outputs ?? []).map(o => [o.value, o.label]), settings.audio_output);
        this._install.set(languages, this._installLanguage ?? settings.language);

        const target = settings.translate_to ?? '';
        this._speakIn.set([['', 'Off · read in the text language'],
            ...languages.filter(([v]) => v !== settings.language)], target);
        const endpoint = settings.translator_endpoint ?? SERVERS[0][1];
        const servers = SERVERS.map(([name, url]) => [url, `${name} (${url.replace(/^https?:\/\//, '')})`]);
        if (!SERVERS.some(([, url]) => url === endpoint))
            servers.push([endpoint, endpoint]);
        this._translator.set([...servers, ['nllb', OFFLINE]], settings.translator === 'nllb' ? 'nllb' : endpoint);
        const models = [...new Set([...(state.translator_models ?? []), settings.translator_model].filter(Boolean))];
        this._model.set(models.map(m => [m, m]), settings.translator_model);
        const offline = settings.translator === 'nllb';
        this._translator.row.visible = Boolean(target);
        this._model.row.visible = Boolean(target) && !offline;
        this._offlineRow.visible = Boolean(target) && offline && (!state.nllb_ready || state.installing_translator);
        this._offlineButton.label = state.installing_translator ? 'Cancel' : 'Install';
        this._testRow.visible = Boolean(target);
        this._testRow.subtitle = state.translation_status ?? '';

        if (!this._serverFilled && state.settings) {
            // The fields start from the server in use (or the last one tried) and are then the user's.
            this._serverFilled = true;
            this._endpointRow.text = settings.online_endpoint ?? 'https://api.openai.com/v1';
            this._modelRow.text = settings.online_model ?? '';
            this._voiceIdRow.text = settings.online_voice ?? 'alloy';
            this._rememberRow.active = Boolean(settings.remember_token);
        }
        this._serverActive.subtitle = online
            ? `Speech server · ${settings.online_endpoint} · ${settings.online_model} / ${settings.online_voice}`
            : 'Voices on this computer (Kokoro or Piper)';
        this._localButton.visible = online;
        const speechModels = state.online_models ?? [];
        this._found.set(speechModels.map(m => [m, m]), this._modelRow.text.trim());
        this._found.row.visible = speechModels.length > 0;
        this._tokenRow.title = state.key_ready && this._endpointRow.text.trim() === settings.online_endpoint
            ? 'API key / token (the saved one is used; type to replace it)' : 'API key / token, if the server needs one';
        this._serverTest.subtitle = state.models_loading ? 'Asking the server for its models…'
            : state.testing_voice ? 'Testing the voice…' : state.provider_status || '';
        this._clearToken.visible = Boolean(state.key_ready);
        this._syncServer();

        for (const row of [this._language.row, this._speed, ...Object.values(this._switches), this._areaRow,
            this._voice.row, this._output.row, this._serverActive, this._endpointRow, this._modelRow, this._voiceIdRow,
            this._tokenRow, this._rememberRow, this._serverTest, this._speakIn.row, this._translator.row, this._model.row, this._testRow])
            row.sensitive = ready;
        this._install.row.sensitive = !state.setup_busy;
        this._syncing = false;
    }
}
