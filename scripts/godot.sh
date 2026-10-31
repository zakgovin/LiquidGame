#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export HYDRO_TOOLS="${HYDRO_TOOLS:-/workspace/.hydrologic}"
export XDG_CONFIG_HOME="$HYDRO_TOOLS/config"
export XDG_DATA_HOME="$HYDRO_TOOLS/data"
export XDG_CACHE_HOME="$HYDRO_TOOLS/cache"
export ANDROID_USER_HOME="$HYDRO_TOOLS/android-user"
mkdir -p "$ANDROID_USER_HOME"
cd "$project_dir"
exec "$HYDRO_TOOLS/bin/Godot_v4.6.3-stable_linux.x86_64" --path "$project_dir" "$@"
