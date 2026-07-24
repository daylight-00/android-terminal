# Provisioned upstream assets

These files were acquired by `tools/acquire-web-terminal-assets.sh` from exact-version
official npm package URLs. `ASSET_RECEIPT.json` records package coordinates, verified
npm SHA-512 integrity, acquired tarball SHA-256/size, and every installed file SHA-256/size.
Existing coordinates retain fixed SHA-512 pins; newly connected stable addons resolve and
validate the exact-version registry record before acquisition. Exact package metadata is
retained for official addons that do not need a separately installed license member;
`LICENSE.xterm.txt` contains the upstream xterm.js project license and each retained package
metadata file records its MIT declaration. The application loads production JavaScript only
from its APK assets.
