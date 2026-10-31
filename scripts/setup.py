#!/usr/bin/env python3
"""Verified, local Godot 4.6.3 / Android export tools. No pip dependencies."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import urllib.request
import zipfile

VERSION = "4.6.3"
ROOT = Path(os.environ.get("HYDRO_TOOLS", "/workspace/.hydrologic"))
BASE = f"https://github.com/godotengine/godot/releases/download/{VERSION}-stable/"
ARTIFACTS = {
    "Godot_v4.6.3-stable_linux.x86_64.zip": "a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c",
    "Godot_v4.6.3-stable_export_templates.tpz": "da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68",
}


def download(name, url, digest, algorithm="sha512"):
    path = ROOT / "cache" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        print(f"Downloading {name}", flush=True)
        temp = path.with_suffix(".part")
        with urllib.request.urlopen(url, timeout=120) as source, temp.open("wb") as dest:
            shutil.copyfileobj(source, dest)
        temp.replace(path)
    with path.open("rb") as f:
        actual = hashlib.file_digest(f, algorithm).hexdigest()
    if actual != digest:
        raise RuntimeError(f"Checksum mismatch for {name}; delete {path} and retry")
    print(f"Verified {name}", flush=True)
    return path


def extract(archive, destination, prefixes=None):
    with zipfile.ZipFile(archive) as z:
        for member in z.infolist():
            if prefixes and member.filename not in prefixes:
                continue
            z.extract(member, destination)
            mode = member.external_attr >> 16
            if mode & stat.S_IXUSR:
                (destination / member.filename).chmod(0o755)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--android", action="store_true")
    args = parser.parse_args()
    ROOT.mkdir(parents=True, exist_ok=True)
    binary = ROOT / "bin" / "Godot_v4.6.3-stable_linux.x86_64"
    if not binary.exists():
        existing = shutil.which("godot")
        if existing and subprocess.check_output([existing, "--version"], text=True).startswith(VERSION):
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.symlink_to(Path(existing).resolve())
        else:
            name = "Godot_v4.6.3-stable_linux.x86_64.zip"
            extract(download(name, BASE + name, ARTIFACTS[name]), binary.parent)
    print(f"Godot: {binary}", flush=True)
    if not args.android:
        return
    templates = ROOT / "data/godot/export_templates/4.6.3.stable"
    if not (templates / "android_debug.apk").exists():
        name = "Godot_v4.6.3-stable_export_templates.tpz"
        archive = download(name, BASE + name, ARTIFACTS[name])
        wanted = ["android_debug.apk", "android_release.apk", "linux_debug.x86_64", "linux_release.x86_64", "version.txt"]
        with zipfile.ZipFile(archive) as z:
            templates.mkdir(parents=True, exist_ok=True)
            for name in wanted:
                with z.open("templates/" + name) as source, (templates / name).open("wb") as dest:
                    shutil.copyfileobj(source, dest)
                if name.startswith("linux_"):
                    (templates / name).chmod(0o755)
    sdk = ROOT / "android-sdk"
    # SHA-1 values published by Google's signed-over-TLS repository2-3.xml.
    for name, checksum, folder in [
        ("build-tools_r36_linux.zip", "b0b6376977657e8ad9b969bacf4093601da2c6fb", "build-tools/36.0.0"),
        ("platform-tools_r37.0.1-linux.zip", "477254aa5f903c15cf51001717bdf347fb6b53e0", "platform-tools"),
    ]:
        target = sdk / folder
        if target.exists():
            continue
        archive = download(name, "https://dl.google.com/android/repository/" + name, checksum, "sha1")
        staging = ROOT / "cache" / (name + ".unpacked")
        extract(archive, staging)
        children = list(staging.iterdir())
        if len(children) != 1:
            raise RuntimeError(f"Unexpected SDK layout: {name}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(children[0]), target)
        staging.rmdir()
    java = Path(shutil.which("java")).resolve().parent.parent
    if not (java / "bin/jarsigner").exists():
        # The managed Debian image includes a JRE only. Complete its exact
        # matching JDK in the writable tools directory, never in /usr.
        version = subprocess.run([str(java / "bin/java"), "-version"], capture_output=True, text=True, check=True).stderr
        if "21.0.12.1" not in version:
            raise RuntimeError("Install a complete JDK 21 (including jarsigner) and rerun setup.")
        package = download(
            "openjdk-21-jdk-headless.deb",
            "https://deb.debian.org/debian/pool/main/o/openjdk-21/openjdk-21-jdk-headless_21.0.12.1+1-1~deb13u1_amd64.deb",
            "f3abafb6c644b03df042824e707cd211ea33254761d7f7b75be3f8dc0df97c7a", "sha256")
        local_java = ROOT / "jdk/usr/lib/jvm/java-21-openjdk-amd64"
        if not (local_java / "bin/jarsigner").exists():
            shutil.copytree(java, local_java, symlinks=True, dirs_exist_ok=True)
            subprocess.run(["dpkg-deb", "-x", str(package), str(ROOT / "jdk")], check=True)
        java = local_java
    config = ROOT / "config/godot/editor_settings-4.6.tres"
    config.parent.mkdir(parents=True, exist_ok=True)
    keystore = ROOT / "debug.keystore"
    if not keystore.exists():
        subprocess.run(["keytool", "-genkeypair", "-keystore", str(keystore), "-storepass", "android", "-alias", "androiddebugkey", "-keypass", "android", "-dname", "CN=Android Debug,O=Android,C=US", "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000"], check=True)
    config.write_text(f'''[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "{java}"
export/android/android_sdk_path = "{sdk}"
export/android/debug_keystore = "{keystore}"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
''')
    print("Android APK export tools ready (debug signing only).", flush=True)


if __name__ == "__main__":
    main()
