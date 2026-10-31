#!/usr/bin/env python3
"""Build the volumetric fluid extension for the editor and Android."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

import setup

PROJECT = Path(__file__).resolve().parent.parent
CPP = setup.ROOT / "godot-cpp-4.5"
NDK_VERSION = "28.1.13356709"


def build(android=False):
    if not (CPP / "SConstruct").exists():
        archive = setup.download(
            "godot-cpp-4.5-stable.zip",
            "https://codeload.github.com/godotengine/godot-cpp/zip/refs/tags/godot-4.5-stable",
            "0316ea168750b5f4f1caea6457657a6c64241f890f78e2f042aee4be2b1085bf", "sha256")
        staging = setup.ROOT / "cache/cpp-unpacked"
        setup.extract(archive, staging)
        shutil.move(str(staging / "godot-cpp-godot-4.5-stable"), CPP)
        staging.rmdir()
    python_packages = setup.ROOT / "python"
    if not (python_packages / "SCons").exists():
        subprocess.run([sys.executable, "-m", "pip", "install", "--target", str(python_packages), "scons==4.9.1"], check=True)
    env = os.environ.copy()
    env["HYDRO_CPP_ROOT"] = str(CPP)
    env["PYTHONPATH"] = str(python_packages) + os.pathsep + env.get("PYTHONPATH", "")
    sdk = setup.ROOT / "android-sdk"
    ndk = sdk / "ndk" / NDK_VERSION
    if android and not (ndk / "source.properties").exists():
        archive = setup.download(
            "android-ndk-r28b-linux.zip",
            "https://dl.google.com/android/repository/android-ndk-r28b-linux.zip",
            "f574d3165405bd59ffc5edaadac02689075a729f", "sha1")
        staging = setup.ROOT / "cache/ndk-unpacked"
        setup.extract(archive, staging)
        ndk.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staging / "android-ndk-r28b"), ndk)
        staging.rmdir()
    env["ANDROID_HOME"] = str(sdk)
    targets = [("linux", "x86_64")]
    if android:
        targets.extend([("android", "arm64"), ("android", "x86_64")])
    for platform, arch in targets:
        print(f"Building native water: {platform} / {arch}", flush=True)
        subprocess.run([
            sys.executable, "-m", "SCons", f"-j{min(os.cpu_count() or 2, 4)}",
            f"platform={platform}", f"arch={arch}", "target=template_release",
            "android_api_level=24", f"build_profile={PROJECT / 'native/build_profile.json'}",
            "debug_symbols=no"], cwd=PROJECT / "native", env=env, check=True)
        library = PROJECT / f"native/bin/libhydrologic.{platform}.template_release.{arch}.so"
        strip = str(ndk / "toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip") if platform == "android" else "strip"
        subprocess.run([strip, "--strip-unneeded", str(library)], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--android", action="store_true")
    build(parser.parse_args().android)
