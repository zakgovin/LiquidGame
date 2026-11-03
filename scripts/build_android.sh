#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
touch build/.gdignore
python3 scripts/build_native.py --android
./scripts/godot.sh --headless --editor --import
./scripts/godot.sh --headless --export-debug Android build/hydrologic-0.16.1-android.apk
"${HYDRO_TOOLS:-/workspace/.hydrologic}/android-sdk/build-tools/36.0.0/apksigner" verify --verbose build/hydrologic-0.16.1-android.apk
