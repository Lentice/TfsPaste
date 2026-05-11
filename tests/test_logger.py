import logging
import pytest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from logger import setup_logging


@pytest.fixture(autouse=True)
def reset_root_logger():
    yield
    root = logging.getLogger()
    for h in root.handlers[:]:
        h.close()
        root.removeHandler(h)
    root.setLevel(logging.WARNING)


def test_debug_true_sets_debug_level():
    setup_logging(debug=True, log_console=False, log_file=False)
    assert logging.getLogger().level == logging.DEBUG


def test_debug_false_sets_info_level():
    setup_logging(debug=False, log_console=False, log_file=False)
    assert logging.getLogger().level == logging.INFO


def test_no_handlers_when_both_disabled():
    setup_logging(debug=False, log_console=False, log_file=False)
    assert logging.getLogger().handlers == []


def test_log_console_adds_stream_handler():
    setup_logging(debug=False, log_console=True, log_file=False)
    handlers = logging.getLogger().handlers
    stream_handlers = [h for h in handlers
                       if isinstance(h, logging.StreamHandler)
                       and not isinstance(h, logging.FileHandler)]
    assert len(stream_handlers) == 1


def test_log_file_adds_file_handler(tmp_path, monkeypatch):
    monkeypatch.setenv('TEMP', str(tmp_path))
    setup_logging(debug=False, log_console=False, log_file=True)
    file_handlers = [h for h in logging.getLogger().handlers
                     if isinstance(h, logging.FileHandler)]
    assert len(file_handlers) == 1


def test_log_file_overwrites_on_each_call(tmp_path, monkeypatch):
    monkeypatch.setenv('TEMP', str(tmp_path))
    setup_logging(debug=False, log_console=False, log_file=True)
    logging.getLogger('test').info('first run')
    for h in logging.getLogger().handlers:
        h.close()
    logging.getLogger().handlers.clear()

    setup_logging(debug=False, log_console=False, log_file=True)
    log_file = tmp_path / 'TFS Paster' / 'TFS Paster.log'
    content = log_file.read_text(encoding='utf-8')
    assert 'first run' not in content


def test_setup_logging_replaces_previous_handlers():
    setup_logging(debug=False, log_console=True, log_file=False)
    setup_logging(debug=False, log_console=True, log_file=False)
    stream_handlers = [h for h in logging.getLogger().handlers
                       if isinstance(h, logging.StreamHandler)
                       and not isinstance(h, logging.FileHandler)]
    assert len(stream_handlers) == 1
