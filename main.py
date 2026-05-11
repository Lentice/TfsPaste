import sys
import os
import time
import logging
import threading
import subprocess
from pathlib import Path

import win32api
import win32con
import win32gui

from config import load_config, AppConfig
from gui import StatusWindow
from hotkey import HotkeyListener
from keyboard import send_ctrl, send_key, send_backspace
from logger import setup_logging
from clipboard import (
    backup_clipboard, restore_clipboard, read_html, write_html,
    wait_clipboard_idle,
)
from html_processor import (
    get_source_url, pre_shrink_html, post_shrink_html,
    update_header_description,
)
from image_handler import patch_images

_INI_PATH = Path(__file__).parent / 'Config.ini'
_LOG_PATH = Path(os.environ['TEMP']) / 'TFS Paster' / 'TFS Paster Log'
_PID_FILE = Path(os.environ['TEMP']) / 'TFS Paster' / 'tfs_paster.pid'


def _enforce_single_instance() -> None:
    _PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    if _PID_FILE.exists():
        try:
            old_pid = int(_PID_FILE.read_text().strip())
            result = subprocess.run(
                ['taskkill', '/F', '/PID', str(old_pid)],
                capture_output=True, check=False,
            )
            if result.returncode == 0:
                time.sleep(0.3)
        except (ValueError, OSError):
            pass
    _PID_FILE.write_text(str(os.getpid()))

_log = logging.getLogger(__name__)

_BROWSERS = ('- Google Chrome', '— Mozilla Firefox', '- Microsoft​ Edge')


class TfsPasterApp:
    def __init__(self, cfg: AppConfig):
        self._cfg = cfg
        self._browser_hwnd: int = 0
        self._browser_active: bool = False
        self._clipboard_backup: dict = {}
        self._gui: StatusWindow | None = None
        self._listener: HotkeyListener | None = None

    # ── GUI helpers ────────────────────────────────────────────────
    def _normal(self, msg: str) -> None:
        _log.info(msg)
        if self._gui:
            self._gui.normal_status(msg)

    def _success(self, msg: str) -> None:
        _log.info(msg)
        if self._gui:
            self._gui.success_status(msg)

    def _error(self, msg: str) -> None:
        _log.error(msg)
        if self._gui:
            self._gui.error_status(msg)

    # ── Window helpers ─────────────────────────────────────────────
    def _is_browser_active(self) -> bool:
        self._browser_active = (win32gui.GetForegroundWindow() == self._browser_hwnd)
        if not self._browser_active:
            self._error('Web browser is not active')
        return self._browser_active

    def _wait_keys_released(self) -> None:
        keys = [0x10, 0x11, 0x12, 0x5B, 0x5C]  # Shift, Ctrl, Alt, LWin, RWin
        while any(win32api.GetAsyncKeyState(k) & 0x8000 for k in keys):
            time.sleep(0.01)

    # ── Debug helpers ──────────────────────────────────────────────
    def _save_debug(self, filename: str, content: str) -> None:
        _LOG_PATH.mkdir(parents=True, exist_ok=True)
        (_LOG_PATH / filename).write_bytes(content.encode('utf-8'))

    # ── Main job ───────────────────────────────────────────────────
    def do_job(self) -> None:
        cfg = self._cfg
        t = cfg.timing

        self._browser_hwnd = win32gui.GetForegroundWindow()
        title = win32gui.GetWindowText(self._browser_hwnd)

        if not any(b in title for b in _BROWSERS):
            self._error('Active window is not a browser')
            return

        self._normal('Waiting keys release...')
        self._wait_keys_released()

        self._normal('Waiting clipboard idle...')
        if not wait_clipboard_idle(t.clipboard_idle_timeout_ms, t.clipboard_poll_interval_ms):
            self._error('Clipboard idle timeout')
            return

        self._clipboard_backup = backup_clipboard()

        time.sleep(t.clipboard_read_delay_ms / 1000)
        html = read_html()
        if html is None:
            self._error('No HTML format in clipboard')
            restore_clipboard(self._clipboard_backup)
            return

        if cfg.debug:
            self._save_debug('Source.html', html)

        source_url = get_source_url(html)
        _log.info("SourceURL: %s", source_url)

        self._normal('Patching HTML...')
        if cfg.pre_shrink_html:
            html = pre_shrink_html(html)

        html = patch_images(html, source_url, self._is_browser_active, t)

        if not self._browser_active:
            restore_clipboard(self._clipboard_backup)
            return

        if cfg.post_shrink_html:
            html = post_shrink_html(html)
        html = update_header_description(html)

        self._normal('Updating clipboard...')
        time.sleep(t.clipboard_write_delay_ms / 1000)
        write_html(html)
        wait_clipboard_idle(t.clipboard_idle_timeout_ms, t.clipboard_poll_interval_ms)

        if cfg.debug:
            patched = read_html()
            if patched:
                self._save_debug('Patched.html', patched)

        if not self._is_browser_active():
            restore_clipboard(self._clipboard_backup)
            return

        time.sleep(t.operation_interval_ms / 1000)
        send_ctrl(ord('A'), t.key_press_duration_ms)
        time.sleep(t.operation_interval_ms / 1000)
        send_backspace(4, t.key_press_duration_ms)
        time.sleep(t.operation_interval_ms / 1000)
        send_ctrl(ord('V'), t.key_press_duration_ms, t.paste_delay_ms)
        wait_clipboard_idle(t.clipboard_idle_timeout_ms, t.clipboard_poll_interval_ms)

        restore_clipboard(self._clipboard_backup)
        self._success('DONE')

    def _on_hotkey(self) -> None:
        threading.Thread(target=self.do_job, daemon=True, name='DoJob').start()

    def _on_exit(self) -> None:
        if self._listener:
            self._listener.stop()
        restore_clipboard(self._clipboard_backup)
        sys.exit(0)

    def run(self) -> None:
        hk = self._cfg.hotkey
        parts = (
            (['Ctrl'] if hk.ctrl else []) +
            (['Alt'] if hk.alt else []) +
            (['Shift'] if hk.shift else []) +
            [hk.key.upper()]
        )
        label = ' + '.join(parts)

        self._gui = StatusWindow(label, self._on_exit)
        self._listener = HotkeyListener(hk.ctrl, hk.alt, hk.shift, hk.key, self._on_hotkey)
        self._listener.start()
        _log.info("Hotkey: %s", label)
        _log.info("Debug dump path: %s", _LOG_PATH)
        self._gui.run()


def main() -> None:
    _enforce_single_instance()
    cfg = load_config(_INI_PATH)
    setup_logging(cfg.debug, cfg.log_console, cfg.log_file)
    app = TfsPasterApp(cfg)

    if len(sys.argv) > 1 and sys.argv[1].lower() == 'quiet':
        app.do_job()
        return

    app.run()


if __name__ == '__main__':
    main()
