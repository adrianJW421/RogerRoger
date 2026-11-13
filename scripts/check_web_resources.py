#!/usr/bin/env python3
"""Verify shipped HTML and each local asset through the running HTTP service."""
import argparse
import re
import urllib.parse
import urllib.request
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, default=Path('/Applications/VibeCast.app'))
parser.add_argument('--phone-url', required=True)
parser.add_argument('--config-url', default='http://127.0.0.1:8786/')
args = parser.parse_args()
ROOT = args.app / 'Contents/Resources/VibeCast_VibeCast.bundle/Contents/Resources/web'
PHONE = args.phone_url.rstrip('/') + '/'
CONFIG = args.config_url.rstrip('/') + '/'
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
checked = {}

def check(url, expected=None):
    if url in checked:
        if expected is not None:
            assert checked[url] == expected, f'Served content differs from installed resource: {url}'
        return checked[url]
    with opener.open(url, timeout=5) as response:
        body = response.read()
        assert response.status == 200, (url, response.status)
        if expected is not None:
            assert body == expected, f'Served content differs from installed resource: {url}'
        suffix = urllib.parse.urlsplit(url).path.rsplit('.', 1)[-1]
        if suffix == 'js':
            assert response.headers.get_content_type() == 'text/javascript', url
        if suffix == 'css':
            assert response.headers.get_content_type() == 'text/css', url
    checked[url] = body
    return body

for origin, page in [(PHONE, 'index.html'), (CONFIG, 'config.html')]:
    html = check(urllib.parse.urljoin(origin, page), (ROOT / page).read_bytes()).decode()
    for reference in re.findall(r'(?:src|href)=["\']([^"\']+)', html):
        if reference.startswith(('./', '/')):
            check(urllib.parse.urljoin(origin, reference))

for path in ROOT.rglob('*'):
    if path.is_file() and path.suffix in {'.js', '.css', '.svg', '.png', '.webmanifest'}:
        relative = path.relative_to(ROOT).as_posix()
        check(urllib.parse.urljoin(PHONE, relative), path.read_bytes())
print(f'PASS: {len(checked)} HTML/asset URLs returned HTTP 200 with installed content and correct script/style MIME types')
