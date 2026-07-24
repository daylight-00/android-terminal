#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/android-terminal-completion.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

python3 "$ROOT/tools/verify-layer2-completion.py" "$ROOT"

copy_fixture() {
  local destination=$1
  mkdir -p -- "$destination"
  tar -C "$ROOT" --exclude=.git --exclude=out -cf - app docs tools | tar -C "$destination" -xf -
}

CSP_NEGATIVE=$TMP/csp-negative
copy_fixture "$CSP_NEGATIVE"
python3 - "$CSP_NEGATIVE/app/src/main/kotlin/io/github/daylight00/androidterminal/LocalAssetWebViewClient.kt" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text(); p.write_text(s.replace(" 'wasm-unsafe-eval'", "", 1))
PY
if python3 "$ROOT/tools/verify-layer2-completion.py" "$CSP_NEGATIVE" >/dev/null 2>&1; then
  echo 'FAIL layer2-completion-csp-negative unexpectedly passed' >&2
  exit 1
fi
echo 'PASS layer2-completion-csp-negative'

PIN_NEGATIVE=$TMP/pin-negative
copy_fixture "$PIN_NEGATIVE"
python3 - "$PIN_NEGATIVE/docs/layer2-completion.json" <<'PY'
from pathlib import Path
import json, sys
p=Path(sys.argv[1]); d=json.loads(p.read_text()); d['upstream']['automatic_addons'].remove('@xterm/addon-image@0.9.0'); p.write_text(json.dumps(d, indent=2)+'\n')
PY
if python3 "$ROOT/tools/verify-layer2-completion.py" "$PIN_NEGATIVE" >/dev/null 2>&1; then
  echo 'FAIL layer2-completion-pin-negative unexpectedly passed' >&2
  exit 1
fi
echo 'PASS layer2-completion-pin-negative'


ACCOUNT_NEGATIVE=$TMP/account-negative
copy_fixture "$ACCOUNT_NEGATIVE"
python3 - "$ACCOUNT_NEGATIVE/docs/layer2-completion.json" <<'PYNEG'
from pathlib import Path
import json, sys
p=Path(sys.argv[1])
d=json.loads(p.read_text())
d['account_session']['shared_storage']['home_link']='HOME/storage'
p.write_text(json.dumps(d, indent=2)+'\n')
PYNEG
if python3 "$ROOT/tools/verify-layer2-completion.py" "$ACCOUNT_NEGATIVE" >/dev/null 2>&1; then
  echo 'FAIL layer2-completion-account-negative unexpectedly passed' >&2
  exit 1
fi
echo 'PASS layer2-completion-account-negative'

SAF_INBOX_NEGATIVE=$TMP/saf-inbox-negative
copy_fixture "$SAF_INBOX_NEGATIVE"
python3 - "$SAF_INBOX_NEGATIVE/docs/layer2-completion.json" <<'PYNEG'
from pathlib import Path
import json, sys
p=Path(sys.argv[1])
d=json.loads(p.read_text())
d['account_session']['saf']['fixed_home_inbox']='HOME/imports'
p.write_text(json.dumps(d, indent=2)+'\n')
PYNEG
if python3 "$ROOT/tools/verify-layer2-completion.py" "$SAF_INBOX_NEGATIVE" >/dev/null 2>&1; then
  echo 'FAIL layer2-completion-saf-inbox-negative unexpectedly passed' >&2
  exit 1
fi
echo 'PASS layer2-completion-saf-inbox-negative'
