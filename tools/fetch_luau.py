"""Install a fixed official Luau release for local checks and CI."""
from pathlib import Path
import hashlib
import io
import os
import platform
import urllib.request
import zipfile

VERSION = '0.744'
ARCHIVES = {
    'Windows': ('luau-windows.zip', 'fde3e22c557aac6afe20a34e8050b7d8c290fa42638c04274a307ed5d0ef0db8'),
    'Linux': ('luau-ubuntu.zip', '6506f0852c623aaffcb28494aac16c26dc04a269ea0e16cc0aafc8c8ac79f3ec'),
    'Darwin': ('luau-macos.zip', 'ae34a55253bd7eb291723ffdf0143d59128a42b6e62f774ee6f6fbfbef8e5a06'),
}

def main():
    name, digest = ARCHIVES[platform.system()]
    url = f'https://github.com/luau-lang/luau/releases/download/{VERSION}/{name}'
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != digest:
        raise SystemExit('Unexpected toolchain checksum')
    target = Path(__file__).resolve().parents[1]/'.tools/luau'
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for item in archive.infolist():
            filename = Path(item.filename).name
            if filename not in {'luau', 'luau.exe', 'luau-compile', 'luau-compile.exe', 'luau-analyze', 'luau-analyze.exe'}:
                continue
            path = target/filename
            path.write_bytes(archive.read(item))
            if os.name != 'nt':
                path.chmod(0o755)
    print('Installed Luau '+VERSION)

if __name__ == '__main__':
    main()
