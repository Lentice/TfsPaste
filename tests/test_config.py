import pytest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from config import load_config

def write_ini(tmp_path, content):
    f = tmp_path / 'Config.ini'
    f.write_text(content, encoding='utf-8')
    return f

def test_defaults(tmp_path):
    ini = write_ini(tmp_path, '[General]\n')
    cfg = load_config(ini)
    assert cfg.debug == False
    assert cfg.pre_shrink_html == False
    assert cfg.post_shrink_html == False
    assert cfg.hotkey.ctrl == False
    assert cfg.hotkey.alt == True
    assert cfg.hotkey.shift == True
    assert cfg.hotkey.key == 'd'
    assert cfg.timing.operation_interval_ms == 100
    assert cfg.timing.clipboard_idle_timeout_ms == 15000
    assert cfg.timing.image_capture_timeout_ms == 8000

def test_timing_section(tmp_path):
    ini = write_ini(tmp_path, '[Timing]\nPasteDelayMs=300\nOperationIntervalMs=200\n')
    cfg = load_config(ini)
    assert cfg.timing.paste_delay_ms == 300
    assert cfg.timing.operation_interval_ms == 200

def test_backward_compat_op_latency(tmp_path):
    ini = write_ini(tmp_path, '[General]\nOpLatencyMs=250\n')
    cfg = load_config(ini)
    assert cfg.timing.operation_interval_ms == 250

def test_timing_overrides_legacy(tmp_path):
    ini = write_ini(tmp_path, '[General]\nOpLatencyMs=250\n[Timing]\nOperationIntervalMs=999\n')
    cfg = load_config(ini)
    assert cfg.timing.operation_interval_ms == 999

def test_hotkey_config(tmp_path):
    ini = write_ini(tmp_path, '[Hotkey]\nCTRL=1\nALT=0\nSHIFT=1\nKEY=f\n')
    cfg = load_config(ini)
    assert cfg.hotkey.ctrl == True
    assert cfg.hotkey.alt == False
    assert cfg.hotkey.key == 'f'

def test_debug_flag(tmp_path):
    ini = write_ini(tmp_path, '[General]\nDebug=1\n')
    cfg = load_config(ini)
    assert cfg.debug == True

def test_log_defaults(tmp_path):
    ini = write_ini(tmp_path, '[General]\n')
    cfg = load_config(ini)
    assert cfg.log_console == True
    assert cfg.log_file == True


def test_log_console_disabled(tmp_path):
    ini = write_ini(tmp_path, '[General]\nLogConsole=0\n')
    cfg = load_config(ini)
    assert cfg.log_console == False


def test_log_file_disabled(tmp_path):
    ini = write_ini(tmp_path, '[General]\nLogFile=0\n')
    cfg = load_config(ini)
    assert cfg.log_file == False
