#!/usr/bin/env bash
# Runs every tests/tst_*.qml with Qt Quick Test, every tests/test_*.py with unittest, and the pill's fit
# check (scripts/fit.sh), the transport centring check (scripts/centring.sh), the scroll bar and caption check
# (scripts/scrollbar.sh), the shared components check (scripts/components.sh), the launcher service check (scripts/launcher.sh), the SectionHost and Theme wiring check
# (scripts/wiring.sh), the lock's Auth and Idle checks (scripts/lock-qml.sh) and the unlock check (scripts/auth.sh, which
# only ever uses a dummy PAM folder) in Quickshell. An empty set is a pass.
set -euo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"

# TZ is pinned: the DST tests in tst_themeMode.qml (the ones guarded by brussels()) need Europe/Brussels's clock
# changes, and skip in any other zone. tst_themeModeTz.qml needs a zone whose DST changes at midnight, so it skips in
# that run and gets one of its own in Atlantic/Azores.
if compgen -G "$dir/tests/tst_*.qml" >/dev/null; then
    TZ=Europe/Brussels QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input "$dir/tests"
    TZ=Atlantic/Azores QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input "$dir/tests/tst_themeModeTz.qml"
else
    echo "test: no QML tests"
fi

if compgen -G "$dir/tests/test_*.py" >/dev/null; then
    python3 -m unittest discover -s "$dir/tests" -p 'test_*.py'
else
    echo "test: no Python tests"
fi

"$dir/scripts/fit.sh"
"$dir/scripts/centring.sh"
"$dir/scripts/scrollbar.sh"
"$dir/scripts/components.sh"
"$dir/scripts/launcher.sh"
"$dir/scripts/wiring.sh"
"$dir/scripts/lock-qml.sh"
"$dir/scripts/auth.sh"
