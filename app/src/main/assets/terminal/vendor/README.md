# Provisioned upstream assets

These files were acquired by `tools/acquire-web-terminal-assets.sh` from the pinned
official npm package URLs. `ASSET_RECEIPT.json` records the package coordinates,
fixed npm SHA-512 integrity, acquired tarball SHA-256/size, and every installed file
SHA-256/size. Exact package metadata is retained for official addons that do not
need a separately installed license member; `LICENSE.xterm.txt` contains the upstream
xterm.js project license and each retained package metadata file records its MIT declaration.
The application loads
production JavaScript only from its APK assets.
