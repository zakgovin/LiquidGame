#!/usr/bin/env python3
"""Build an unsigned iPhone IPA, a portable Xcode project and a tested simulator app.

Run on macOS with Xcode. No Apple account, certificate or provisioning profile
is used; signing with a personal Apple ID is a separate installation step.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import time
import zipfile

import setup

PROJECT = Path(__file__).resolve().parent.parent
OUTPUT = PROJECT / "build/ios"
CPP = setup.ROOT / "godot-cpp-4.5"
MIN_IOS = "13.0"
MAC_EDITOR = "Godot_v4.6.3-stable_macos.universal.zip"
MAC_SHA512 = "0155bbc8dcf179edab4ef08e3dbbd4480d7434ab1990cb3fb25517d453b1b65787c7fe6dfc8824b15ff25e1fdcec59e8584f765054106894fee00311868c3964"
BUNDLE_ID = "com.zakgovin.hydrologic"


def run(args, *, env=None, capture=False, timeout=None):
    args = [str(a) for a in args]
    print("+ " + " ".join(args), flush=True)
    result = subprocess.run(args, cwd=PROJECT, env=env, check=True,
                            text=True, stdout=subprocess.PIPE if capture else None,
                            timeout=timeout)
    return result.stdout.strip() if capture else None


def tools():
    binary = setup.ROOT / "bin/Godot.app/Contents/MacOS/Godot"
    if not binary.exists():
        setup.extract(setup.download(MAC_EDITOR, setup.BASE + MAC_EDITOR, MAC_SHA512), setup.ROOT / "bin")
    templates = setup.ROOT / "data/godot/export_templates/4.6.3.stable"
    if not (templates / "ios.zip").exists():
        name = "Godot_v4.6.3-stable_export_templates.tpz"
        archive = setup.download(name, setup.BASE + name, setup.ARTIFACTS[name])
        templates.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as z:
            with z.open("templates/ios.zip") as source, (templates / "ios.zip").open("wb") as dest:
                shutil.copyfileobj(source, dest)
    # Godot follows macOS's standard Application Support directory, not
    # XDG_DATA_HOME. Keep the verified template in the cache and expose it
    # at the path actually used by the macOS editor.
    mac_templates = Path.home() / "Library/Application Support/Godot/export_templates/4.6.3.stable"
    mac_templates.mkdir(parents=True, exist_ok=True)
    installed = mac_templates / "ios.zip"
    if not installed.exists():
        installed.symlink_to(templates / "ios.zip")
    if not (CPP / "SConstruct").exists():
        archive = setup.download("godot-cpp-4.5-stable.zip",
            "https://codeload.github.com/godotengine/godot-cpp/zip/refs/tags/godot-4.5-stable",
            "0316ea168750b5f4f1caea6457657a6c64241f890f78e2f042aee4be2b1085bf", "sha256")
        staging = setup.ROOT / "cache/cpp-unpacked"
        setup.extract(archive, staging)
        shutil.move(str(staging / "godot-cpp-godot-4.5-stable"), CPP)
        staging.rmdir()
    packages = setup.ROOT / "python"
    if not (packages / "SCons").exists():
        run([sys.executable, "-m", "pip", "install", "--target", packages, "scons==4.9.1"])
    env = os.environ.copy()
    env.update(HYDRO_CPP_ROOT=str(CPP), PYTHONPATH=str(packages) + os.pathsep + env.get("PYTHONPATH", ""))
    for name, path in {"XDG_DATA_HOME": "data", "XDG_CONFIG_HOME": "config", "XDG_CACHE_HOME": "cache"}.items():
        env[name] = str(setup.ROOT / path)
    return binary, env


def native(env):
    (PROJECT / "native/obj").mkdir(parents=True, exist_ok=True)
    (PROJECT / "native/obj/.gdignore").touch()
    arch = "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64"
    scons = [sys.executable, "-m", "SCons", f"-j{min(os.cpu_count() or 2, 4)}", "target=template_release",
             f"build_profile={PROJECT / 'native/build_profile.json'}", "debug_symbols=no"]
    def build(*options):
        subprocess.run(scons + list(options), cwd=PROJECT / "native", env=env, check=True)
    build("platform=macos", f"arch={arch}")
    host_name = f"libhydrologic.macos.template_release.{arch}.dylib"
    shutil.copy2(PROJECT / "native/obj" / host_name, PROJECT / "native/bin" / host_name)
    toolchain = run(["xcode-select", "-p"], capture=True)
    libraries = {}
    for target_arch, simulator in [("arm64", False), ("arm64", True), ("x86_64", True)]:
        suffix = f".ios.template_release.{target_arch}" + (".simulator" if simulator else "")
        build("platform=ios", f"arch={target_arch}", f"ios_simulator={'yes' if simulator else 'no'}",
              f"ios_min_version={MIN_IOS}", f"IOS_TOOLCHAIN_PATH={toolchain}/Toolchains/XcodeDefault.xctoolchain")
        destination = OUTPUT / "native" / ("simulator-" + target_arch if simulator else "device") / "libhydrologic.a"
        destination.parent.mkdir(parents=True, exist_ok=True)
        # StaticLibrary archives do not link LIBS. Merge godot-cpp as well so
        # the exported project is self-contained and has no missing C++ API.
        run(["xcrun", "libtool", "-static", "-o", destination,
             PROJECT / "native/obj" / ("libhydrologic" + suffix + ".a"),
             CPP / "bin" / ("libgodot-cpp" + suffix + ".a")])
        libraries[(target_arch, simulator)] = destination
    simulator_lib = OUTPUT / "native/simulator/libhydrologic.a"
    simulator_lib.parent.mkdir(parents=True, exist_ok=True)
    run(["xcrun", "lipo", "-create", libraries[("arm64", True)], libraries[("x86_64", True)], "-output", simulator_lib])
    xcframework = PROJECT / "native/bin/hydrologic.xcframework"
    if xcframework.exists():
        shutil.rmtree(xcframework)
    run(["xcodebuild", "-create-xcframework", "-library", libraries[("arm64", False)],
         "-library", simulator_lib, "-output", xcframework])
    info = xcframework / "Info.plist"
    data = plistlib.loads(info.read_bytes())
    for lib in data["AvailableLibraries"]:
        # Godot uses BinaryPath to distinguish static XCFramework slices
        # from embedded frameworks that would need a signing identity.
        lib["BinaryPath"] = lib["LibraryPath"]
    info.write_bytes(plistlib.dumps(data))
    return arch


def export(binary, env):
    destination = PROJECT / "build/ios-project"
    destination.mkdir(parents=True, exist_ok=True)
    run([binary, "--path", PROJECT, "--headless", "--editor", "--import"], env=env)
    run([binary, "--path", PROJECT, "--headless", "--export-release", "iOS", destination / "Hydrologic.ipa"], env=env)
    project = destination / "Hydrologic.xcodeproj"
    pbx = project / "project.pbxproj"
    text = pbx.read_text()
    # UNSIGNED00 is only Godot's nonempty-template marker, never an Apple
    # identity. Remove it before building or distributing the Xcode project.
    text = re.sub(r'((?:DEVELOPMENT_TEAM|DevelopmentTeam)\s*=\s*)"?UNSIGNED00"?;',
                  r'\1"";', text)
    text = text.replace('CODE_SIGN_IDENTITY = "Apple Distribution";', 'CODE_SIGN_IDENTITY = "Apple Development";')
    text = text.replace('$linker_flags', '')
    text, linker_settings = re.subn(r'(OTHER_LDFLAGS\s*=\s*")([^\n]*)(";)',
                  r'\1\2 -Wl,-u,_hydrologic_library_init -Wl,-exported_symbol,_hydrologic_library_init\3', text)
    if linker_settings < 2:
        raise RuntimeError("Could not preserve the water initializer in both Xcode configurations")
    if "UNSIGNED00" in text:
        raise RuntimeError("Template team marker was not removed")
    pbx.write_text(text)
    for path in destination.rglob("*.plist"):
        if "xcframework" in str(path):
            continue
        content = path.read_bytes()
        if b"UNSIGNED00" in content:
            path.write_bytes(content.replace(b"UNSIGNED00", b""))
    return project


def xcode(project, *, simulator, arch):
    derived = OUTPUT / ("derived-simulator" if simulator else "derived-device")
    args = ["xcodebuild", "-project", project, "-scheme", "Hydrologic", "-configuration", "Release",
            "-destination", "generic/platform=iOS Simulator" if simulator else "generic/platform=iOS",
            "-derivedDataPath", derived, "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGN_IDENTITY=", "DEVELOPMENT_TEAM=", f"IPHONEOS_DEPLOYMENT_TARGET={MIN_IOS}"]
    if simulator:
        run(args + ["-sdk", "iphonesimulator", f"ARCHS={arch}", "ONLY_ACTIVE_ARCH=YES", "build"])
        return derived / "Build/Products/Release-iphonesimulator/Hydrologic.app"
    archive = OUTPUT / "Hydrologic.xcarchive"
    run(args + ["-archivePath", archive, "SKIP_INSTALL=NO", "archive"])
    return archive / "Products/Applications/Hydrologic.app"


def verify(app, simulator=False):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == BUNDLE_ID
    expected = "iPhoneSimulator" if simulator else "iPhoneOS"
    assert expected in info["CFBundleSupportedPlatforms"], info["CFBundleSupportedPlatforms"]
    executable = app / info["CFBundleExecutable"]
    # iOS archives strip the ordinary nlist table. Runtime dlsym resolves
    # the dyld export trie instead, so inspect the actual exported symbols.
    symbols = run(["xcrun", "dyld_info", "-exports", executable], capture=True)
    if "_hydrologic_library_init" not in symbols:
        print(symbols[-3000:])
        raise RuntimeError("The water initializer is absent from the iOS runtime export table")
    assert (app / "Hydrologic.pck").exists(), "Game resources missing"
    if not simulator:
        assert not (app / "embedded.mobileprovision").exists()
        assert not (app / "_CodeSignature").exists()
        assert "arm64" in run(["xcrun", "lipo", "-archs", executable], capture=True)
    return info


def smoke(app):
    # Ad-hoc signing is local simulator integrity, not an Apple account or
    # a device installation certificate. The device IPA stays unsigned.
    run(["codesign", "--force", "--deep", "--sign", "-", app])
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "--json"], capture=True))["devices"]
    choices = [d for runtime in sorted(devices, reverse=True) if "iOS" in runtime
               for d in devices[runtime] if d.get("isAvailable") and d["name"].startswith("iPhone")]
    if not choices:
        raise RuntimeError("No available iPhone Simulator")
    device = choices[0]
    if device["state"] != "Booted":
        run(["xcrun", "simctl", "boot", device["udid"]])
    run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"], timeout=240)
    run(["xcrun", "simctl", "install", device["udid"], app])
    run(["xcrun", "simctl", "launch", "--terminate-running-process", "--stdout", OUTPUT / "simulator-stdout.log",
         "--stderr", OUTPUT / "simulator-stderr.log", device["udid"], BUNDLE_ID, "--", "--capture", "user://ios-smoke.png"])
    container = Path(run(["xcrun", "simctl", "get_app_container", device["udid"], BUNDLE_ID, "data"], capture=True))
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        screenshots = list(container.rglob("ios-smoke.png"))
        if screenshots and screenshots[0].stat().st_size > 4096:
            shutil.copy2(screenshots[0], OUTPUT / "hydrologic-simulator.png")
            break
        time.sleep(1)
    else:
        for path in OUTPUT.glob("simulator-*.log"):
            print(path.read_text(errors="replace")[-12000:])
        raise RuntimeError("iOS game did not produce its rendered native-water screenshot")
    for path in OUTPUT.glob("simulator-*.log"):
        text = path.read_text(errors="replace")
        if "SCRIPT ERROR:" in text or "Error loading extension" in text:
            raise RuntimeError(f"Simulator reported an initialization error: {path}")
    run(["xcrun", "simctl", "shutdown", device["udid"]])
    return device["name"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-simulator", action="store_true", help="Build only the unsigned device app and Xcode project")
    args = parser.parse_args()
    if platform.system() != "Darwin" or not shutil.which("xcodebuild"):
        raise SystemExit("iOS compilation requires macOS and Xcode; use the repository's iOS workflow.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (PROJECT / "build/.gdignore").touch()
    binary, env = tools()
    arch = native(env)
    project = export(binary, env)
    device_app = xcode(project, simulator=False, arch=arch)
    info = verify(device_app)
    version = info["CFBundleShortVersionString"]
    payload = OUTPUT / "package/Payload"
    payload.mkdir(parents=True, exist_ok=True)
    shutil.copytree(device_app, payload / device_app.name, dirs_exist_ok=True)
    ipa = OUTPUT / f"hydrologic-{version}-ios-unsigned.ipa"
    run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", payload, ipa])
    readme = PROJECT / "docs/IOS.ru.md"
    if readme.exists():
        shutil.copy2(readme, project.parent / "INSTALL.ru.md")
    xcode_zip = OUTPUT / f"hydrologic-{version}-xcode.zip"
    run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", project.parent, xcode_zip])
    report = {"version": version, "bundle_id": BUNDLE_ID, "build": info["CFBundleVersion"],
              "device_arch": "arm64", "minimum_ios": MIN_IOS, "signed": False,
              "godot": setup.VERSION, "native_solver": "linked static godot-cpp 4.5"}
    artifacts = [ipa, xcode_zip]
    if not args.skip_simulator:
        simulator_app = xcode(project, simulator=True, arch=arch)
        verify(simulator_app, simulator=True)
        report["simulator_tested"] = smoke(simulator_app)
        simulator_zip = OUTPUT / f"hydrologic-{version}-simulator.zip"
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", simulator_app, simulator_zip])
        artifacts.append(simulator_zip)
    sums = []
    for path in artifacts:
        with path.open("rb") as file:
            digest = hashlib.file_digest(file, "sha256").hexdigest()
        sums.append(f"{digest}  {path.name}")
    (OUTPUT / "SHA256SUMS").write_text("\n".join(sums) + "\n")
    (OUTPUT / "build-info.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
