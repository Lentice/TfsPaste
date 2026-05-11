import logging
import time
import win32api
import win32con

_log = logging.getLogger(__name__)


def send_key(vk: int, duration_ms: int = 50):
    _log.debug("send_key vk=0x%02X duration=%dms", vk, duration_ms)
    win32api.keybd_event(vk, 0, 0, 0)
    time.sleep(duration_ms / 1000)
    win32api.keybd_event(vk, 0, win32con.KEYEVENTF_KEYUP, 0)


def send_ctrl(key_vk: int, duration_ms: int = 50, after_ms: int = 0):
    _log.debug("send_ctrl key=0x%02X duration=%dms after=%dms", key_vk, duration_ms, after_ms)
    win32api.keybd_event(win32con.VK_CONTROL, 0, 0, 0)
    time.sleep(duration_ms / 1000)
    win32api.keybd_event(key_vk, 0, 0, 0)
    time.sleep(duration_ms / 1000)
    win32api.keybd_event(key_vk, 0, win32con.KEYEVENTF_KEYUP, 0)
    win32api.keybd_event(win32con.VK_CONTROL, 0, win32con.KEYEVENTF_KEYUP, 0)
    if after_ms:
        time.sleep(after_ms / 1000)


def send_backspace(count: int = 1, duration_ms: int = 50):
    _log.debug("send_backspace count=%d duration=%dms", count, duration_ms)
    for _ in range(count):
        send_key(win32con.VK_BACK, duration_ms)
