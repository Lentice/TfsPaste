import re
import time
import os
from typing import Optional, Callable

import win32api
import win32con

from clipboard import put_file_to_clipboard, wait_clipboard_idle, read_html
from html_processor import to_pixel
from keyboard import send_ctrl, send_key, send_backspace

_IMG_EXTS = r'\.(?:gif|jpg|bmp|png|jpeg|apng|svg|tif|tiff|ico|cur|webp)'

def get_src_from_html(html: str, tag_name: str) -> Optional[tuple[str, str]]:
    pattern = rf'(?is)<{re.escape(tag_name)}[^>]+src="(?!https?://)([^"]*{_IMG_EXTS}\??[^"]*)"'
    m = re.search(pattern, html)
    if not m:
        return None
    ext_m = re.search(_IMG_EXTS, m.group(1), re.IGNORECASE)
    return (m.group(1), ext_m.group(0)) if ext_m else None

def get_style_value(html: str, name: str, conv_to_pixel: bool = False) -> Optional[object]:
    pattern = rf'(?si)[\s\n]style=[^>]*?["\';s]{re.escape(name)}:(.*?)[;"\']'
    m = re.search(pattern, html)
    if not m:
        return None
    val = m.group(1).strip()
    if conv_to_pixel:
        try:
            return to_pixel(val)
        except ValueError:
            return None
    return val

def get_file_path(path: str, source_url: str) -> Optional[str]:
    m = re.match(r'^file:/+(.*)$', path)
    if m:
        fp = m.group(1)
        return fp if os.path.exists(fp) else None

    if source_url:
        dir_m = re.match(r'(?:file:/+)(.*/).*', source_url)
        if dir_m:
            candidate = dir_m.group(1) + path
            if os.path.exists(candidate):
                return candidate
    return None

def parse_remote_url_from_clip() -> Optional[str]:
    html = read_html()
    if not html:
        return None
    m = re.search(r'(?i)src="(https?[^"]+)"', html)
    return m.group(1) if m else None

def upload_to_web(
    filepath: str,
    is_browser_active: Callable[[], bool],
    timing,
    log: Callable[[str], None],
) -> Optional[str]:
    log(f"Uploading: {filepath}")
    if not put_file_to_clipboard(filepath):
        return None
    if not is_browser_active():
        return None

    time.sleep(timing.image_upload_before_ms / 1000)

    send_ctrl(ord('A'), timing.key_press_duration_ms)
    time.sleep(timing.operation_interval_ms / 1000)
    send_backspace(4, timing.key_press_duration_ms)
    time.sleep(timing.operation_interval_ms / 1000)
    send_ctrl(ord('V'), timing.key_press_duration_ms, timing.paste_delay_ms)

    if not wait_clipboard_idle(timing.clipboard_idle_timeout_ms, timing.clipboard_poll_interval_ms):
        log("ERROR: Clipboard idle timeout after paste")
        return None

    time.sleep(timing.image_upload_after_ms / 1000)

    deadline = time.monotonic() + timing.image_capture_timeout_ms / 1000
    while time.monotonic() < deadline:
        send_ctrl(ord('A'), timing.key_press_duration_ms)
        time.sleep(timing.operation_interval_ms / 1000)
        send_ctrl(ord('C'), timing.key_press_duration_ms, timing.copy_delay_ms)

        if not wait_clipboard_idle(timing.clipboard_idle_timeout_ms, timing.clipboard_poll_interval_ms):
            log("ERROR: Clipboard idle timeout after copy")
            return None

        url = parse_remote_url_from_clip()
        if url:
            log(f"Got URL: {url}")
            time.sleep(max(timing.operation_interval_ms, 50) / 1000)
            send_key(win32con.VK_BACK, timing.key_press_duration_ms)
            return url

        if not is_browser_active():
            return None
        time.sleep(timing.image_capture_poll_interval_ms / 1000)

    log("ERROR: Image capture timeout")
    return None

def patch_images(
    html: str,
    source_url: str,
    is_browser_active: Callable[[], bool],
    timing,
    log: Callable[[str], None],
) -> str:
    if is_browser_active():
        html = _patch_exist_img(html, source_url, is_browser_active, timing, log)
    if is_browser_active():
        html = _patch_v_shape(html, source_url, is_browser_active, timing, log)
    return html

def _patch_exist_img(html, source_url, is_browser_active, timing, log) -> str:
    for img in re.findall(r'(?s)(<img[^>]+src="[^">]+".*?>)', html):
        info = get_src_from_html(img, 'img')
        if not info:
            continue
        fp = get_file_path(info[0], source_url)
        if not fp:
            continue
        url = upload_to_web(fp, is_browser_active, timing, log)
        if not is_browser_active():
            return html
        if url:
            new_img = re.sub(r'(\s|\n)src="[^"]+"', f' src="{url}"', img)
            html = html.replace(img, new_img, 1)
    return html

def _patch_v_shape(html, source_url, is_browser_active, timing, log) -> str:
    for vs in re.findall(r'(?s)(<v:shape\s.*?</v:shape>)', html):
        img_tag = _vshape_to_img(vs, source_url, is_browser_active, timing, log)
        if img_tag:
            html = html.replace(vs, img_tag, 1)
        if not is_browser_active():
            return html
    return html

def _vshape_to_img(vs, source_url, is_browser_active, timing, log) -> Optional[str]:
    info = get_src_from_html(vs, 'v:imagedata')
    if not info:
        return None
    fp = get_file_path(info[0], source_url)
    if not fp:
        return None
    url = upload_to_web(fp, is_browser_active, timing, log)
    if not url:
        return None

    w = get_style_value(vs, 'width', conv_to_pixel=True)
    h = get_style_value(vs, 'height', conv_to_pixel=True)
    attrs = ''
    if w is not None:
        attrs += f' width="{int(w)}" max-width="{int(w)}"'
    if h is not None:
        attrs += f' height="{int(h)}"'
    return f'<img{attrs} src="{url}">'
