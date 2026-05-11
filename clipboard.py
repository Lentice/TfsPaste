import logging
import struct
import time
import win32clipboard
import win32con
from typing import Optional

_log = logging.getLogger(__name__)

CF_HTML: int = win32clipboard.RegisterClipboardFormat("HTML Format")

# These formats use GDI handles that cannot be round-tripped as raw bytes
_SKIP_ON_BACKUP: frozenset[int] = frozenset({
    3,   # CF_METAFILEPICT - requires GetMetafileBitsEx
    14,  # CF_ENHMETAFILE  - requires SetEnhMetaFileBits to restore
})


def _try_open(hwnd: int = 0) -> bool:
    try:
        win32clipboard.OpenClipboard(hwnd)
        return True
    except Exception as e:
        _log.debug("OpenClipboard failed: %s", e)
        return False


def wait_clipboard_idle(timeout_ms: int = 15000, poll_ms: int = 10) -> bool:
    deadline = time.monotonic() + timeout_ms / 1000
    while time.monotonic() < deadline:
        if _try_open(0):
            win32clipboard.CloseClipboard()
            return True
        time.sleep(poll_ms / 1000)
    _log.warning("Clipboard idle timeout after %d ms", timeout_ms)
    return False


def backup_clipboard() -> dict:
    result: dict[int, bytes] = {}
    if not _try_open(0):
        return result
    try:
        fmt = win32clipboard.EnumClipboardFormats(0)
        while fmt:
            if fmt in _SKIP_ON_BACKUP:
                fmt = win32clipboard.EnumClipboardFormats(fmt)
                continue
            try:
                data = win32clipboard.GetClipboardData(fmt)
                if isinstance(data, bytes):
                    result[fmt] = data
                elif isinstance(data, str):
                    result[fmt] = data.encode('utf-16-le')
            except Exception as e:
                _log.debug("GetClipboardData fmt=%d skipped: %s", fmt, e)
            fmt = win32clipboard.EnumClipboardFormats(fmt)
    finally:
        win32clipboard.CloseClipboard()
    _log.debug("Clipboard backed up: %d formats", len(result))
    return result


def restore_clipboard(backup: dict) -> None:
    if not backup:
        return
    if not _try_open(0):
        return
    try:
        win32clipboard.EmptyClipboard()
        for fmt, data in backup.items():
            try:
                win32clipboard.SetClipboardData(fmt, data)
            except Exception as e:
                _log.warning("SetClipboardData fmt=%d failed: %s", fmt, e)
    finally:
        win32clipboard.CloseClipboard()
    _log.debug("Clipboard restored: %d formats", len(backup))


def read_html() -> Optional[str]:
    try:
        win32clipboard.OpenClipboard(0)
        data = win32clipboard.GetClipboardData(CF_HTML)
        win32clipboard.CloseClipboard()
        result = data.decode('utf-8') if isinstance(data, bytes) else data
        _log.debug("read_html: %d bytes", len(result))
        return result
    except Exception as e:
        _log.debug("read_html failed: %s", e)
        try:
            win32clipboard.CloseClipboard()
        except Exception:
            pass
        return None


def write_html(html: str) -> bool:
    try:
        encoded = html.encode('utf-8')
        win32clipboard.OpenClipboard(0)
        win32clipboard.EmptyClipboard()
        win32clipboard.SetClipboardData(CF_HTML, encoded)
        win32clipboard.CloseClipboard()
        _log.debug("write_html: %d bytes", len(encoded))
        return True
    except Exception as e:
        _log.warning("write_html failed: %s", e)
        try:
            win32clipboard.CloseClipboard()
        except Exception:
            pass
        return False


def put_file_to_clipboard(filepath: str) -> bool:
    """Put a single file path on clipboard as CF_HDROP (for pasting into browser)."""
    try:
        path_w = (filepath + '\0\0').encode('utf-16-le')
        # DROPFILES: pFiles=20, pt.x=0, pt.y=0, fNC=0, fWide=1 (5 x DWORD = 20 bytes)
        header = struct.pack('IIIII', 20, 0, 0, 0, 1)
        data = header + path_w
        win32clipboard.OpenClipboard(0)
        win32clipboard.EmptyClipboard()
        win32clipboard.SetClipboardData(win32con.CF_HDROP, data)
        win32clipboard.CloseClipboard()
        _log.debug("put_file_to_clipboard: %s", filepath)
        return True
    except Exception as e:
        _log.warning("put_file_to_clipboard failed: %s", e)
        try:
            win32clipboard.CloseClipboard()
        except Exception:
            pass
        return False
