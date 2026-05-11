import configparser
from dataclasses import dataclass, field
from pathlib import Path

@dataclass
class TimingConfig:
    key_press_duration_ms: int = 50
    key_release_wait_ms: int = 200
    paste_delay_ms: int = 150
    copy_delay_ms: int = 150
    clipboard_read_delay_ms: int = 100
    clipboard_write_delay_ms: int = 100
    clipboard_idle_timeout_ms: int = 15000
    clipboard_poll_interval_ms: int = 10
    image_upload_before_ms: int = 200
    image_upload_after_ms: int = 500
    image_capture_timeout_ms: int = 8000
    image_capture_poll_interval_ms: int = 100
    operation_interval_ms: int = 100

@dataclass
class HotkeyConfig:
    ctrl: bool = False
    alt: bool = True
    shift: bool = True
    key: str = 'd'

@dataclass
class AppConfig:
    debug: bool = False
    pre_shrink_html: bool = False
    post_shrink_html: bool = False
    hotkey: HotkeyConfig = field(default_factory=HotkeyConfig)
    timing: TimingConfig = field(default_factory=TimingConfig)

def load_config(ini_path: str | Path) -> AppConfig:
    p = configparser.ConfigParser()
    p.read(ini_path, encoding='utf-8')

    legacy_latency = p.getint('General', 'OpLatencyMs', fallback=100)

    timing = TimingConfig(
        key_press_duration_ms=p.getint('Timing', 'KeyPressDurationMs', fallback=50),
        key_release_wait_ms=p.getint('Timing', 'KeyReleaseWaitMs', fallback=200),
        paste_delay_ms=p.getint('Timing', 'PasteDelayMs', fallback=150),
        copy_delay_ms=p.getint('Timing', 'CopyDelayMs', fallback=150),
        clipboard_read_delay_ms=p.getint('Timing', 'ClipboardReadDelayMs', fallback=100),
        clipboard_write_delay_ms=p.getint('Timing', 'ClipboardWriteDelayMs', fallback=100),
        clipboard_idle_timeout_ms=p.getint('Timing', 'ClipboardIdleTimeoutMs', fallback=15000),
        clipboard_poll_interval_ms=p.getint('Timing', 'ClipboardPollIntervalMs', fallback=10),
        image_upload_before_ms=p.getint('Timing', 'ImageUploadBeforeMs', fallback=200),
        image_upload_after_ms=p.getint('Timing', 'ImageUploadAfterMs', fallback=500),
        image_capture_timeout_ms=p.getint('Timing', 'ImageCaptureTimeoutMs', fallback=8000),
        image_capture_poll_interval_ms=p.getint('Timing', 'ImageCapturePollIntervalMs', fallback=100),
        operation_interval_ms=p.getint('Timing', 'OperationIntervalMs', fallback=legacy_latency),
    )

    hotkey = HotkeyConfig(
        ctrl=p.getboolean('Hotkey', 'CTRL', fallback=False),
        alt=p.getboolean('Hotkey', 'ALT', fallback=True),
        shift=p.getboolean('Hotkey', 'SHIFT', fallback=True),
        key=p.get('Hotkey', 'KEY', fallback='d').lower(),
    )

    return AppConfig(
        debug=p.getboolean('General', 'Debug', fallback=False),
        pre_shrink_html=p.getboolean('General', 'PreShrinkHtml', fallback=False),
        post_shrink_html=p.getboolean('General', 'PostShrinkHtml', fallback=False),
        hotkey=hotkey,
        timing=timing,
    )
