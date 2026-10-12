"""Bundle application sources and the corresponding LGPL dependency sources."""
import hashlib
import os
import pathlib
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
cache = pathlib.Path(os.environ.get('AFT_CACHE', root / '.build/deps'))
out = root / 'dist/Android-File-Transfer-Mac-ARM-Sources.zip'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for folder in ('Sources', 'Resources', 'Tests', 'scripts', '.github'):
        for p in sorted((root / folder).rglob('*')):
            if p.is_file(): z.write(p, 'Android-File-Transfer-for-Mac-ARM/' + str(p.relative_to(root)))
    for name in ('README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', '.gitignore'):
        z.write(root / name, 'Android-File-Transfer-for-Mac-ARM/' + name)
    for name in ('libusb-1.0.29.tar.bz2', 'libmtp-1.1.22.tar.gz'):
        z.write(cache / name, 'Android-File-Transfer-for-Mac-ARM/vendor-sources/' + name)
    for p in (root / '.build/licenses').glob('*'):
        z.write(p, 'Android-File-Transfer-for-Mac-ARM/licenses/' + p.name)
with (root / 'dist/SHA256SUMS.txt').open('w') as f:
    for p in sorted((root / 'dist').glob('*.zip')):
        f.write(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n')
print(out)
