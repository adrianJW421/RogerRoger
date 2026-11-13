"""Small reproducible Java Android build using the existing local Android SDK."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import zipfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent
config_file = root / '.local/toolchain.json'
local_config = json.loads(config_file.read_text()) if config_file.exists() else {}
java_home = os.environ.get('VIBECAST_JAVA_HOME') or local_config.get('javaHome') or os.environ.get('JAVA_HOME')
sdk_home = os.environ.get('VIBECAST_ANDROID_HOME') or local_config.get('androidHome') or os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
if not java_home or not sdk_home:
    raise SystemExit('Set VIBECAST_JAVA_HOME (JDK 17) and VIBECAST_ANDROID_HOME (Android SDK), or create .local/toolchain.json; see README.md.')
jdk = Path(java_home).expanduser() / 'bin'
sdk = Path(sdk_home).expanduser()
bt = sdk / 'build-tools/36.0.0'
android = sdk / 'platforms/android-36/android.jar'
for required in [jdk / 'java', jdk / 'javac', jdk / 'keytool', android, bt / 'aapt2', bt / 'zipalign', bt / 'lib/d8.jar', bt / 'lib/apksigner.jar']:
    if not required.is_file():
        raise SystemExit(f'Missing build tool: {required}')
build = root / 'build'
if build.exists(): shutil.rmtree(build)
for folder in ['classes', 'dex', 'tests']:
    (build / folder).mkdir(parents=True, exist_ok=True)
(root / 'dist').mkdir(exist_ok=True)
local = root / '.local'
local.mkdir(exist_ok=True)

def run(*args):
    subprocess.run([str(x) for x in args], check=True, cwd=root)

libs = []
for entry in json.loads((root / 'dependencies.json').read_text()):
    path = root / 'lib' / entry['file']
    if hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
        raise SystemExit(f'Unverified dependency: {path.name}')
    libs.append(path)
run(jdk / 'javac', '--release', '8', '-encoding', 'UTF-8', '-d', build / 'tests',
    *[root / ('src/local/vibecast/mic/' + name + '.java') for name in ['FollowSegment', 'RecordingGate', 'StopDrain', 'SendQueue']],
    *sorted((root / 'tests').glob('*.java')))
test_reports = []
for test in ['FollowSegmentTest', 'RecordingGateTest', 'StopAndSendTest']:
    result = subprocess.run([str(jdk / 'java'), '-cp', str(build / 'tests'), 'local.vibecast.mic.' + test],
                            cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(result.stdout, end='')
    result.check_returncode()
    test_reports.append(result.stdout.strip())
run(jdk / 'javac', '-source', '8', '-target', '8', '-encoding', 'UTF-8',
    '-cp', os.pathsep.join(map(str, [android, *libs])), '-d', build / 'classes', *sorted((root / 'src').rglob('*.java')))
with zipfile.ZipFile(build / 'classes.jar', 'w') as jar:
    for path in (build / 'classes').rglob('*.class'): jar.write(path, path.relative_to(build / 'classes'))
run(jdk / 'java', '-cp', bt / 'lib/d8.jar', 'com.android.tools.r8.D8', '--min-api', '31',
    '--lib', android, '--output', build / 'dex', build / 'classes.jar', *libs)
run(bt / 'aapt2', 'compile', '--dir', root / 'res', '-o', build / 'res.zip')
run(bt / 'aapt2', 'link', '-o', build / 'unsigned.apk', '--manifest', root / 'AndroidManifest.xml', '-I', android, '-R', build / 'res.zip')
with zipfile.ZipFile(build / 'unsigned.apk', 'a', compression=zipfile.ZIP_DEFLATED) as apk:
    for path in (build / 'dex').glob('*.dex'): apk.write(path, path.name)
    apk.write(root / 'NOTICE.md', 'assets/NOTICE.md')
    apk.write(root / 'LICENSE', 'assets/LICENSE')
    apk.write(root / 'APACHE-2.0.txt', 'assets/APACHE-2.0.txt')
run(bt / 'zipalign', '-f', '4', build / 'unsigned.apk', build / 'aligned.apk')
key = local / 'preview.keystore'
if not key.exists():
    run(jdk / 'keytool', '-genkeypair', '-keystore', key, '-storepass', 'android', '-keypass', 'android',
        '-alias', 'preview', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=RogerRoger Local Preview')
    key.chmod(0o600)
version = ET.parse(root / 'AndroidManifest.xml').getroot().get('{http://schemas.android.com/apk/res/android}versionName')
apk = root / f'dist/RogerRoger-Mic-{version}.apk'
run(jdk / 'java', '-jar', bt / 'lib/apksigner.jar', 'sign', '--ks', key, '--ks-pass', 'pass:android', '--out', apk, build / 'aligned.apk')
run(jdk / 'java', '-jar', bt / 'lib/apksigner.jar', 'verify', '--verbose', apk)
print('Built:', apk, apk.stat().st_size, 'bytes')

# Each rebuild gets its own provenance; never carry forward acceptance of a different APK.
manifest = ET.parse(root / 'AndroidManifest.xml').getroot()
metadata = {
    'version': version,
    'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
    'tests': test_reports,
    'signature': 'apksigner verify --verbose succeeded',
    'permissions': [node.get('{http://schemas.android.com/apk/res/android}name')
                    for node in manifest.findall('uses-permission')],
    'sourceSha256': {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in sorted((root / 'src').rglob('*.java'))},
    'buildScriptSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'artifactStatus': 'Local build only; user-accepted installed artifacts are archived separately in repository .local/accepted/'
}
(root / 'dist/build-info.json').write_text(json.dumps(metadata, indent=2) + '\n')
