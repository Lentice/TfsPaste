# Logging Design — TFS Paster

**Date:** 2026-05-11
**Status:** Approved

## Goal

Add structured Python `logging` to all modules for easier debugging, with output configurable to console and/or log file via `Config.ini`.

---

## Architecture

### New file: `logger.py`

```python
def setup_logging(debug: bool, log_console: bool, log_file: bool) -> None
```

- Sets root logger level to `DEBUG` if `debug=True`, else `INFO`
- Adds `StreamHandler` (stderr) when `log_console=True`
- Adds `FileHandler` (write mode, overwrites on each startup) when `log_file=True`
- Log format: `[HH:MM:SS.mmm] LEVEL     module: message`
- Log file path: `%TEMP%\TFS Paster\TFS Paster.log`

Called once from `main()` in `main.py`, after `load_config()` (config values are needed to configure handlers). `_log = logging.getLogger(__name__)` at module level is fine before `setup_logging` runs — handlers are simply absent until then.

---

## Config.ini Changes

New keys in `[General]` section:

```ini
[General]
LogConsole = true
LogFile    = true
```

Both default to `true` if absent. Read in `load_config()` and stored in `AppConfig`.

---

## AppConfig Changes

```python
@dataclass
class AppConfig:
    debug: bool = False
    log_console: bool = True
    log_file: bool = True
    pre_shrink_html: bool = False
    post_shrink_html: bool = False
    hotkey: HotkeyConfig = ...
    timing: TimingConfig = ...
```

---

## Module-by-Module Changes

### `main.py`
- Remove `logging.basicConfig(...)` block (lines 47–52, currently at module level)
- In `main()`: call order becomes `_enforce_single_instance()` → `load_config()` → `setup_logging(cfg.debug, cfg.log_console, cfg.log_file)`
- Keep existing `_log = logging.getLogger(__name__)` and all existing log calls
- Update `patch_images()` call: remove `_log.info` argument (image_handler now uses its own logger)

### `hotkey.py`
- Add `_log = logging.getLogger(__name__)` at module level
- `_run()`: log successful RegisterHotKey, log failure before raising
- `_run()` message loop: log hotkey triggered event at DEBUG level
- `stop()`: log unregister action at DEBUG level

### `clipboard.py`
- Add `_log = logging.getLogger(__name__)` at module level
- `_try_open()`: log exception at `DEBUG` level instead of swallowing silently
- `backup_clipboard()`: log number of formats backed up at DEBUG; log exceptions at WARNING
- `restore_clipboard()`: log exceptions at WARNING
- `read_html()`: log success (data length) at DEBUG; log failure at DEBUG
- `write_html()`: log success/failure at DEBUG; log exceptions at WARNING
- `put_file_to_clipboard()`: log success/failure; log exceptions at WARNING
- `wait_clipboard_idle()`: log timeout at WARNING

### `image_handler.py`
- Add `_log = logging.getLogger(__name__)` at module level
- Remove `log: Callable[[str], None]` parameter from `upload_to_web()`, `patch_images()`, `_patch_exist_img()`, `_patch_v_shape()`, `_vshape_to_img()`
- Replace all `log(...)` calls with `_log.info(...)` / `_log.warning(...)`
- `upload_to_web()` error strings that start with "ERROR:" become `_log.warning()`

### `html_processor.py`
- Add `_log = logging.getLogger(__name__)` at module level
- `get_source_url()`: log found URL at DEBUG
- `pre_shrink_html()` / `post_shrink_html()`: log entry at DEBUG
- `update_header_description()`: log entry and completion at DEBUG
- `to_pixel()`: log ValueError at DEBUG before raising

### `keyboard.py`
- Add `_log = logging.getLogger(__name__)` at module level
- `send_key()`: log vk code at DEBUG
- `send_ctrl()`: log key combo at DEBUG
- `send_backspace()`: log count at DEBUG

### `gui.py`
- Add `_log = logging.getLogger(__name__)` at module level
- `__init__()`: log window created at DEBUG
- `run()`: log mainloop started at DEBUG

---

## Log File Location

```
%TEMP%\TFS Paster\TFS Paster.log
```

Directory is created by `setup_logging()` if it doesn't exist. File is opened in `'w'` mode (overwrite) each startup.

---

## Log Level Mapping

| `debug` in Config.ini | Root logger level |
|---|---|
| `false` (default) | `INFO` |
| `true` | `DEBUG` |

---

## What Is NOT Changed

- `tests/` — no logging changes to test files
- Log format for existing messages in `main.py` — preserved as-is
- Debug HTML file saving (`_save_debug`) — unchanged, still only active when `debug=True`
