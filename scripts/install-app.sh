#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
import datetime, json, os, pathlib, shutil, subprocess, time, uuid
source = pathlib.Path.cwd() / 'dist/WindowRemember.app'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(source)], check=True)
data = pathlib.Path.home() / 'Library/Application Support/WindowRemember'
backup = data / 'DeploymentBackups' / (datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + str(uuid.uuid4()))
backup.mkdir(parents=True, mode=0o700)
def snapshot(name):
    destination = backup / name
    destination.mkdir(mode=0o700)
    if (data / 'Diagnostics').exists():
        shutil.copytree(data / 'Diagnostics', destination / 'Diagnostics')
    if (data / 'layouts.json').exists():
        shutil.copy2(data / 'layouts.json', destination / 'layouts.json')
snapshot('before-stop')
# SIGTERM is handled by the app to flush queued diagnostics before exiting.
subprocess.run(['killall', '-TERM', 'WindowRemember'], check=False, capture_output=True)
for _ in range(150):
    status = subprocess.run(['pgrep', '-x', 'WindowRemember'], capture_output=True)
    if status.returncode == 1:
        break
    if status.returncode != 0:
        raise RuntimeError('Cannot confirm app stopped; installation aborted, backup retained')
    time.sleep(0.1)
else:
    raise RuntimeError('App did not stop cleanly; installation aborted, backup retained')
snapshot('after-stop')
# Only replace the application bundle. Never remove or replace Application Support.
subprocess.run(['ditto', str(source), '/Applications/WindowRemember.app'], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', '/Applications/WindowRemember.app'], check=True)
subprocess.run(['open', '-g', '/Applications/WindowRemember.app'], check=True)
print('Installed and launched. Private diagnostic/layout backup:', backup)
PY
