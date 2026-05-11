import logging
import re

_log = logging.getLogger(__name__)


def get_source_url(html: str) -> str:
    m = re.search(r'^\s*SourceURL\s*:(.*?)$', html, re.MULTILINE)
    return m.group(1).strip() if m else ''


def pre_shrink_html(html: str) -> str:
    _log.debug("pre_shrink_html: %d chars", len(html))
    html = re.sub(r'(?s)(<!--\s*(?!StartFragment|EndFragment).*?-->)', '', html)
    html = html.replace("'mso-list:Ignore'", "''")
    return html


def post_shrink_html(html: str) -> str:
    _log.debug("post_shrink_html: %d chars", len(html))
    html = re.sub(r'(?s)<v:shapetype(?:>|\s.*?>).*?</v:shapetype>', '', html)
    return html


def _get_bin_pos_regex(text: str, pattern: str, include_pattern: bool) -> int:
    head_pattern = f'(?s)(.*?{pattern})' if include_pattern else f'(?s)(.*?){pattern}'
    m = re.match(head_pattern, text)
    return len(m.group(1).encode('utf-8')) if m else 0


def update_header_description(html: str) -> str:
    _log.debug("update_header_description")

    def _sub(pattern, replacement_fn):
        return re.sub(pattern, replacement_fn, html, count=1)

    html = _sub(
        r'(StartHTML):\d*',
        lambda m: f"{m.group(1)}:{_get_bin_pos_regex(html, '<html', False):010d}",
    )
    html = re.sub(
        r'(EndHTML):\d*',
        lambda m: f"{m.group(1)}:{len(html.encode('utf-8')):010d}",
        html, count=1,
    )
    html = re.sub(
        r'(StartFragment):\d*',
        lambda m: f"{m.group(1)}:{_get_bin_pos_regex(html, r'<!--\s*StartFragment\s*-->', True):010d}",
        html, count=1,
    )
    html = re.sub(
        r'(EndFragment):\d*',
        lambda m: f"{m.group(1)}:{_get_bin_pos_regex(html, r'<!--\s*EndFragment\s*-->', False):010d}",
        html, count=1,
    )
    return html


def to_pixel(size_str: str) -> float:
    m = re.match(r'\s*(\d+(?:\.\d+)?)\s*(pt|px|cm|in|mm)', size_str, re.IGNORECASE)
    if not m:
        _log.debug("to_pixel: cannot parse %r", size_str)
        raise ValueError(f"Cannot parse size: {size_str!r}")
    value, unit = float(m.group(1)), m.group(2).lower()
    conversions = {'pt': 96 / 72, 'px': 1.0, 'cm': 37.795276, 'in': 96.0, 'mm': 3.779528}
    return value * conversions[unit]
