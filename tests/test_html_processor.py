import re
import pytest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from html_processor import (
    get_source_url, pre_shrink_html, post_shrink_html,
    update_header_description, to_pixel,
)

SAMPLE_HEADER = (
    "Version:0.9\r\n"
    "StartHTML:0000000000\r\n"
    "EndHTML:0000000000\r\n"
    "StartFragment:0000000000\r\n"
    "EndFragment:0000000000\r\n"
    "SourceURL:file:///C:/test/doc.html\r\n"
)
SAMPLE_BODY = "<html><body><!--StartFragment--><p>Hi</p><!--EndFragment--></body></html>"
SAMPLE_HTML = SAMPLE_HEADER + SAMPLE_BODY

def test_get_source_url():
    assert get_source_url(SAMPLE_HTML) == 'file:///C:/test/doc.html'

def test_get_source_url_missing():
    assert get_source_url("<html><body></body></html>") == ''

def test_pre_shrink_removes_comments():
    html = '<html><!-- a comment --><p>text</p></html>'
    result = pre_shrink_html(html)
    assert '<!-- a comment -->' not in result
    assert '<p>text</p>' in result

def test_pre_shrink_preserves_fragment_markers():
    html = '<html><!--StartFragment--><p>x</p><!--EndFragment--></html>'
    result = pre_shrink_html(html)
    assert '<!--StartFragment-->' in result
    assert '<!--EndFragment-->' in result

def test_pre_shrink_replaces_mso_list_ignore():
    html = "<span style='mso-list:Ignore'>1.</span>"
    result = pre_shrink_html(html)
    assert "mso-list:Ignore" not in result

def test_post_shrink_removes_vshapetype():
    html = '<html><v:shapetype id="x">data</v:shapetype><p>text</p></html>'
    result = post_shrink_html(html)
    assert '<v:shapetype' not in result
    assert '<p>text</p>' in result

def test_post_shrink_no_vshapetype_unchanged():
    html = '<html><p>plain</p></html>'
    assert post_shrink_html(html) == html

def test_to_pixel_pt():
    assert abs(to_pixel('12pt') - 16.0) < 0.01

def test_to_pixel_cm():
    assert abs(to_pixel('1cm') - 37.795276) < 0.001

def test_to_pixel_px():
    assert to_pixel('100px') == 100.0

def test_to_pixel_in():
    assert abs(to_pixel('1in') - 96.0) < 0.001

def test_to_pixel_mm():
    assert abs(to_pixel('1mm') - 3.779528) < 0.001

def test_to_pixel_invalid():
    with pytest.raises(ValueError):
        to_pixel('12em')

def test_update_header_description():
    result = update_header_description(SAMPLE_HTML)
    start_html = int(re.search(r'StartHTML:(\d{10})', result).group(1))
    end_html = int(re.search(r'EndHTML:(\d{10})', result).group(1))
    start_frag = int(re.search(r'StartFragment:(\d{10})', result).group(1))
    end_frag = int(re.search(r'EndFragment:(\d{10})', result).group(1))

    encoded = result.encode('utf-8')
    assert encoded[start_html:start_html + 6] == b'<html>'
    assert end_html == len(encoded)
    assert encoded[start_frag - len(b'<!--StartFragment-->'):start_frag] == b'<!--StartFragment-->'
    assert encoded[end_frag:end_frag + len(b'<!--EndFragment-->')] == b'<!--EndFragment-->'
