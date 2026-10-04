#!/usr/bin/env python3
"""Build one verified local bundle, then transactionally replace its predecessor."""

import argparse
import base64
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import tempfile

from code_signing import sign, signing_options

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
STATE = ROOT / ".local-builds"
MARKER = "OrbitShift-local-build"


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def real_directory(path):
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        raise RuntimeError(f"Refusing unsafe directory: {path}")
    path.mkdir(parents=True, exist_ok=True)


def info(app):
    path = app / "Contents/Info.plist"
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"Missing regular Info.plist: {app}")
    with path.open("rb") as stream:
        return plistlib.load(stream)


def validate_app(app, name, bundle_id, flavor):
    if app.is_symlink() or not app.is_dir() or BUILD.resolve() not in app.resolve().parents:
        raise RuntimeError(f"Refusing unsafe application: {app}")
    data = info(app)
    for key, expected in {
        "CFBundleIdentifier": bundle_id,
        "CFBundleDisplayName": name,
        "OrbitShiftBuildFlavor": flavor,
        "CFBundleExecutable": "OrbitShift",
    }.items():
        if data.get(key) != expected:
            raise RuntimeError(f"Unexpected {key} in {app}")
    marker = app / "Contents/Resources" / MARKER
    executable = app / "Contents/MacOS/OrbitShift"
    if marker.is_symlink() or not marker.is_file() or marker.read_text() != str(ROOT):
        raise RuntimeError(f"This script does not own {app}")
    if executable.is_symlink() or not executable.is_file():
        raise RuntimeError(f"Missing executable: {app}")
    commands = run("/bin/ps", "-axww", "-o", "command=", capture_output=True, text=True).stdout.splitlines()
    if any(command.strip() == str(executable) or command.strip().startswith(str(executable) + " ") for command in commands):
        raise RuntimeError(f"Quit {name} before rebuilding; the running app is preserved.")
    return data


def stop(signum, _frame):
    raise InterruptedError(f"Build interrupted by signal {signum}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", nargs="?", default="Release", choices=["Debug", "Release"])
    parser.add_argument("flavor", nargs="?", default="development", choices=["development", "distribution"])
    args = parser.parse_args()
    development = args.flavor == "development"
    if not development and args.configuration != "Release":
        parser.error("Distribution builds require Release.")
    signer, signing_arguments = signing_options(args.flavor)
    name = "OrbitShift Dev" if development else "OrbitShift"
    bundle_id = "com.rvrhiv.OrbitShift.dev" if development else "com.rvrhiv.OrbitShift"
    app = BUILD / (name + ".app")
    for path in [BUILD, STATE, ROOT / ".build"]:
        real_directory(path)
    lock = STATE / "package.lock"
    try:
        lock.mkdir()
    except FileExistsError:
        raise RuntimeError(f"Another build owns {lock}. For a stale lock, verify no build is running before removing it.")
    staging = None
    previous = None
    promoted = False
    try:
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, stop)
        old = validate_app(app, name, bundle_id, args.flavor) if app.exists() or app.is_symlink() else {}
        with (ROOT / "Config/App-Info.plist").open("rb") as stream:
            metadata = plistlib.load(stream)
        version = metadata["CFBundleShortVersionString"]
        if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
            raise RuntimeError("Invalid base version.")
        public_key = metadata.get("SUPublicEDKey", "")
        if not development and len(base64.b64decode(public_key, validate=True)) != 32:
            raise RuntimeError("Set OrbitShift's own Sparkle public key in Config/App-Info.plist before distribution builds.")
        counter = STATE / ("dev-" + version)
        number = 0
        if development:
            if counter.is_symlink() or (counter.exists() and not counter.is_file()):
                raise RuntimeError(f"Unsafe build counter: {counter}")
            if counter.exists():
                value = counter.read_text().strip()
                if not re.fullmatch(r"[1-9][0-9]{0,8}", value):
                    raise RuntimeError("Invalid development counter.")
                number = int(value)
            if old.get("CFBundleShortVersionString") == version:
                number = max(number, int(old.get("OrbitShiftDevelopmentBuild", 0)))
            number += 1
            if number > 999999999:
                raise RuntimeError("Development counter is exhausted.")
        configuration = args.configuration.lower()
        command = ["/usr/bin/xcrun", "swift", "build", "--package-path", ROOT,
                   "--configuration", configuration, "--product", "OrbitShift"]
        if not development:
            command += ["--arch", "arm64", "--arch", "x86_64"]
        run(*command)
        # --show-bin-path must use the same architecture options as the build.
        path_command = command.copy()
        product_index = path_command.index("--product")
        del path_command[product_index:product_index + 2]
        binary_path = run(*path_command, "--show-bin-path", capture_output=True, text=True).stdout.strip()
        staging = Path(tempfile.mkdtemp(prefix=".OrbitShift-package-", suffix=".noindex", dir=BUILD))
        staged = staging / (name + ".app")
        for part in ("MacOS", "Resources", "Frameworks"):
            (staged / "Contents" / part).mkdir(parents=True)
        executable = staged / "Contents/MacOS/OrbitShift"
        shutil.copy2(Path(binary_path) / "OrbitShift", executable)
        artifact = ROOT / ".build/artifacts/sparkle/Sparkle"
        frameworks = list((artifact / "Sparkle.xcframework").glob("macos-*/Sparkle.framework"))
        if len(frameworks) != 1:
            raise RuntimeError("Expected the pinned macOS Sparkle framework.")
        framework = staged / "Contents/Frameworks/Sparkle.framework"
        run("/usr/bin/ditto", frameworks[0], framework)
        shutil.copy2(artifact / "LICENSE", staged / "Contents/Resources/Sparkle-LICENSE.txt")
        (staged / "Contents/Resources" / MARKER).write_text(str(ROOT))
        metadata.update(CFBundleName=name, CFBundleDisplayName=name, CFBundleIdentifier=bundle_id,
                        OrbitShiftBuildFlavor=args.flavor)
        if development:
            metadata.update(OrbitShiftDevelopmentBuild=str(number), SUEnableAutomaticChecks=False,
                            CFBundleGetInfoString=f"{name} {version}-dev.{number}")
            # There is deliberately no official update channel in a Dev bundle.
            metadata.pop("SUFeedURL", None)
            metadata.pop("SUPublicEDKey", None)
        with (staged / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(metadata, stream, sort_keys=False)
        run("/usr/bin/xcrun", "swift", ROOT / "Scripts/generate-icon.swift", staged / "Contents/Resources/OrbitShift.icns")
        # SPM may embed its artifact path; shipped bundles must load their own framework.
        load_commands = run("/usr/bin/otool", "-l", executable, capture_output=True, text=True).stdout
        rpaths = re.findall(r"cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset", load_commands)
        for rpath in set(rpaths):
            if rpath.startswith(str(ROOT)):
                run("/usr/bin/install_name_tool", "-delete_rpath", rpath, executable)
        sign(staged, args.flavor, signer, signing_arguments, app if old else None)
        validate_app(staged, name, bundle_id, args.flavor)
        next_counter = staging / "next-counter"
        if development:
            next_counter.write_text(str(number) + "\n")
        # Re-check after compilation: the user may have launched the previous build.
        if app.exists() or app.is_symlink():
            validate_app(app, name, bundle_id, args.flavor)
            previous = staging / "previous.app"
            app.rename(previous)
        staged.rename(app)
        promoted = True
        if development:
            os.replace(next_counter, counter)
        print(f"Built: {app}")
        print(f"Version: {version}-dev.{number}" if development else f"Version: {version}")
    finally:
        if not promoted and previous and previous.exists():
            if app.exists() or app.is_symlink():
                raise RuntimeError(f"Cannot restore previous app. Recovery copy retained at {previous}")
            previous.rename(app)
        if staging and staging.exists():
            shutil.rmtree(staging)
        lock.rmdir()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
