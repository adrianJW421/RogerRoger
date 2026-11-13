"""Fetch pinned Maven Central artifacts; verify official checksums before use."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parent
dest = root / 'lib'
dest.mkdir(exist_ok=True)
coordinates = [
    ('com.squareup.okhttp3', 'okhttp', '4.12.1'),
    ('com.squareup.okio', 'okio-jvm', '3.6.0'),
    ('org.jetbrains.kotlin', 'kotlin-stdlib', '1.9.10'),
    ('org.jetbrains', 'annotations', '13.0'),
]
lock = []
for group, artifact, version in coordinates:
    name = f'{artifact}-{version}.jar'
    url = f'https://repo.maven.apache.org/maven2/{group.replace(".", "/")}/{artifact}/{version}/{name}'
    checksum = subprocess.check_output(['curl', '-fLsS', '--retry', '2', '--retry-all-errors', '--connect-timeout', '10', '--max-time', '30', url + '.sha1'], text=True).strip().split()[0]
    path = dest / name
    if not path.exists() or hashlib.sha1(path.read_bytes()).hexdigest() != checksum:
        subprocess.run(['curl', '-fLsS', '--retry', '2', '--retry-all-errors', '--connect-timeout', '10', '--max-time', '60', url, '-o', str(path)], check=True)
    data = path.read_bytes()
    if hashlib.sha1(data).hexdigest() != checksum:
        path.unlink()
        raise SystemExit(f'Checksum mismatch for {name}')
    lock.append({'file': name, 'url': url, 'sha256': hashlib.sha256(data).hexdigest(), 'license': 'Apache-2.0'})
    print('Verified:', name, len(data), flush=True)
(root / 'dependencies.json').write_text(json.dumps(lock, indent=2) + '\n')
