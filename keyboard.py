import time
import win32api
import win32con

def send_key(vk: int, duration_ms: int = 50):
    win32api.keybd_event(vk, 0, 0, 0)
    time.sleep(duration_ms / 1000)
    win32api.keybd_event(vk, 0, win32con.KEYEVENTF_KEYUP, 0)

def send_ctrl(key_vk: int, duration_ms: int = 50, after_ms: int = 0):
    win32api.keybd_event(win32con.VK_CONTROL, 0, 0, 0)
    time.sleep(duration_ms / 1000)
    win32api.keybd_event(key_vk, 0, 0, 0)
    time.sleep(duration_ms / 1000)
    win32api.keybd_event(key_vk, 0, win32con.KEYEVENTF_KEYUP, 0)
    win32api.keybd_event(win32con.VK_CONTROL, 0, win32con.KEYEVENTF_KEYUP, 0)
    if after_ms:
        time.sleep(after_ms / 1000)

def send_backspace(count: int = 1, duration_ms: int = 50):
    for _ in range(count):
        send_key(win32con.VK_BACK, duration_ms)
