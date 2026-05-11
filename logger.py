import logging
import os
from pathlib import Path

_FMT = '[%(asctime)s.%(msecs)03d] %(levelname)-8s %(name)s: %(message)s'
_DATEFMT = '%H:%M:%S'


def setup_logging(debug: bool, log_console: bool, log_file: bool) -> None:
    root = logging.getLogger()
    for h in root.handlers[:]:
        h.close()
        root.removeHandler(h)
    root.setLevel(logging.DEBUG if debug else logging.INFO)

    formatter = logging.Formatter(_FMT, _DATEFMT)

    if log_console:
        h = logging.StreamHandler()
        h.setFormatter(formatter)
        root.addHandler(h)

    if log_file:
        log_path = Path(os.environ.get('TEMP', '/tmp')) / 'TFS Paster' / 'TFS Paster.log'
        log_path.parent.mkdir(parents=True, exist_ok=True)
        h = logging.FileHandler(log_path, mode='w', encoding='utf-8')
        h.setFormatter(formatter)
        root.addHandler(h)
