import pytest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from image_handler import get_src_from_html, get_style_value, get_file_path, parse_remote_url_from_clip

def test_get_src_from_html_img():
    html = '<img width="100" src="file:///C:/images/photo.png" alt="x">'
    result = get_src_from_html(html, 'img')
    assert result is not None
    assert result[0] == 'file:///C:/images/photo.png'
    assert result[1] == '.png'

def test_get_src_from_html_no_match():
    html = '<img src="https://example.com/img.png">'
    result = get_src_from_html(html, 'img')
    assert result is None

def test_get_src_from_html_vimagedata():
    html = '<v:imagedata src="image001.png" o:title=""/>'
    result = get_src_from_html(html, 'v:imagedata')
    assert result is not None
    assert '.png' in result[0]

def test_get_style_value_width():
    html = '<v:shape style="width:5cm;height:3cm">'
    assert get_style_value(html, 'width') == '5cm'

def test_get_style_value_conv_to_pixel():
    html = '<v:shape style="width:72pt;height:96pt">'
    w = get_style_value(html, 'width', conv_to_pixel=True)
    assert w is not None
    assert abs(w - 96.0) < 0.1

def test_get_file_path_file_url(tmp_path):
    img = tmp_path / 'photo.png'
    img.write_bytes(b'fake')
    url = f'file:///{img.as_posix()}'
    result = get_file_path(url, '')
    assert result is not None
    assert Path(result).exists()

def test_get_file_path_relative_with_source_url(tmp_path):
    img = tmp_path / 'photo.png'
    img.write_bytes(b'fake')
    source_url = f'file:///{tmp_path.as_posix()}/doc.html'
    result = get_file_path('photo.png', source_url)
    assert result is not None

def test_get_file_path_missing_file():
    result = get_file_path('file:///C:/nonexistent/image.png', '')
    assert result is None
