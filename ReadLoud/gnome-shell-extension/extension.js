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

        this._indicator.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const quitItem = new PopupMenu.PopupMenuItem('Quit');
        quitItem.connect('activate', () => this.disable());
        this._indicator.menu.addMenuItem(quitItem);

        Main.panel.addToStatusArea(this.metadata.uuid, this._indicator, 1, 'right');

        this._readState();
        this._updateUI();
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
