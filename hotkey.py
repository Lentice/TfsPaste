import ctypes
import ctypes.wintypes
import threading
from typing import Callable

WM_HOTKEY = 0x0312
WM_QUIT = 0x0012
MOD_ALT = 0x0001
MOD_CTRL = 0x0002
MOD_SHIFT = 0x0004

class HotkeyListener:
    def __init__(self, ctrl: bool, alt: bool, shift: bool, key: str, callback: Callable[[], None]):
        self._modifiers = (
            (MOD_CTRL if ctrl else 0) |
            (MOD_ALT if alt else 0) |
            (MOD_SHIFT if shift else 0)
        )
        self._vk = ord(key.upper())
        self._callback = callback
        self._hotkey_id = 1
        self._thread = threading.Thread(target=self._run, daemon=True, name='HotkeyListener')

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        ctypes.windll.user32.UnregisterHotKey(None, self._hotkey_id)
        if self._thread.ident:
            ctypes.windll.user32.PostThreadMessageA(self._thread.ident, WM_QUIT, 0, 0)

    def _run(self) -> None:
        if not ctypes.windll.user32.RegisterHotKey(None, self._hotkey_id, self._modifiers, self._vk):
            raise RuntimeError(f"RegisterHotKey failed (already registered?)")
        msg = ctypes.wintypes.MSG()
        while ctypes.windll.user32.GetMessageA(ctypes.byref(msg), None, 0, 0) != 0:
            if msg.message == WM_HOTKEY and msg.wParam == self._hotkey_id:
                threading.Thread(target=self._callback, daemon=True).start()
            ctypes.windll.user32.TranslateMessage(ctypes.byref(msg))
            ctypes.windll.user32.DispatchMessageA(ctypes.byref(msg))
