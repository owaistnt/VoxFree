import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const STATE_FILE = '/tmp/voxfree/state';
const POLL_INTERVAL = 1000;

export default class VoxFreeExtension extends Extension {
    enable() {
        this._state = 'idle';
        this._lastText = '';
        this._voicesLoaded = false;
        this._voiceItemIndices = [];

        this._indicator = new PanelMenu.Button(0.0, this.metadata.name, false);

        this._icon = new St.Icon({
            icon_name: 'audio-speakers',
            style_class: 'system-status-icon',
        });
        this._indicator.add_child(this._icon);

        this._readItem = new PopupMenu.PopupMenuItem('Read Aloud');
        this._readItem.connect('activate', () => this._exec('voxfree-readloud'));
        this._indicator.menu.addMenuItem(this._readItem);

        this._stopItem = new PopupMenu.PopupMenuItem('Stop Reading');
        this._stopItem.connect('activate', () => this._exec('voxfree-stop-all'));
        this._indicator.menu.addMenuItem(this._stopItem);

        this._replayItem = new PopupMenu.PopupMenuItem('Replay Last');
        this._replayItem.connect('activate', () => this._exec('voxfree-readloud-last'));
        this._indicator.menu.addMenuItem(this._replayItem);

        this._voicesSeparator = new PopupMenu.PopupSeparatorMenuItem('Voices');
        this._voicesSeparatorIndex = this._indicator.menu.addMenuItem(this._voicesSeparator);

        this._indicator.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const quitItem = new PopupMenu.PopupMenuItem('Quit');
        quitItem.connect('activate', () => this.disable());
        this._indicator.menu.addMenuItem(quitItem);

        Main.panel.addToStatusArea(this.metadata.uuid, this._indicator, 1, 'right');

        this._readState();
        this._updateUI();
        this._loadVoices();
        this._timeoutId = GLib.timeout_add(
            GLib.PRIORITY_DEFAULT, POLL_INTERVAL, () => {
                this._readState();
                this._updateUI();
                return GLib.SOURCE_CONTINUE;
            }
        );
    }

    disable() {
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = 0;
        }
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
        this._icon = null;
    }

    _exec(cmd) {
        GLib.spawn_command_line_async(
            `bash -c "nohup ${cmd} >/dev/null 2>&1 &"`
        );
    }

    _loadVoices() {
        // Remove old voice items
        for (const idx of this._voiceItemIndices) {
            this._indicator.menu.removeMenuItem(idx);
        }
        this._voiceItemIndices = [];

        const voiceScripts = [
            '/usr/share/voxfree/lib/list-voices.sh',
            `${GLib.get_home_dir()}/.local/share/voxfree/lib/list-voices.sh`,
        ];

        let voicesOutput = '';
        for (const script of voiceScripts) {
            try {
                const file = Gio.File.new_for_path(script);
                if (file.query_exists(null)) {
                    const [success, stdout] = GLib.spawn_command_line_sync(
                        `bash "${script}"`
                    );
                    if (success) {
                        voicesOutput = stdout.toString();
                        break;
                    }
                }
            } catch (e) {}
        }

        if (!voicesOutput.trim()) {
            const note = new PopupMenu.PopupMenuItem('Install Mimic 3 to select voices');
            note.setSensitive(false);
            this._indicator.menu.insertMenuItem(note, this._voicesSeparatorIndex);
            this._voiceItemIndices.push(this._voicesSeparatorIndex);
            return;
        }

        const lines = voicesOutput.trim().split('\n');
        for (const line of lines) {
            const parts = line.trim().split('|');
            if (parts.length !== 4) continue;
            const voice = parts[1];
            const isCurrent = parts[3].trim();
            const label = isCurrent === '1' ? '\u2713 ' + voice : ' ' + voice;

            const item = new PopupMenu.PopupMenuItem(label);
            item.connect('activate', () => {
                this._exec('voxfree-stop-all');
                this._exec(`voxfree-set-voice ${voice}`);
                GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, () => {
                    this._loadVoices();
                    return GLib.SOURCE_REMOVE;
                });
            });
            const insertIdx = this._voicesSeparatorIndex + 1;
            this._indicator.menu.insertMenuItem(item, insertIdx);
            this._voiceItemIndices.push(insertIdx);
        }
    }

    _readState() {
        try {
            const file = Gio.File.new_for_path(STATE_FILE);
            const [, contents] = file.load_contents(null);
            for (const line of contents.toString().split('\n')) {
                const trimmed = line.trim();
                if (!trimmed.includes('=')) continue;
                const idx = trimmed.indexOf('=');
                const key = trimmed.slice(0, idx).trim();
                const val = trimmed.slice(idx + 1).trim();
                if (key === 'STATE') this._state = val;
                else if (key === 'LAST_TEXT') this._lastText = val;
            }
        } catch {
            this._state = 'idle';
            this._lastText = '';
        }
    }

    _updateUI() {
        const isPlaying = this._state === 'playing';
        this._readItem.visible = !isPlaying;
        this._stopItem.visible = isPlaying;
        this._replayItem.sensitive = Boolean(this._lastText) && !isPlaying;
        if (this._icon) {
            this._icon.icon_name = isPlaying
                ? 'media-playback-stop'
                : 'audio-speakers';
        }
    }
}
