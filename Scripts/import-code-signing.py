#!/usr/bin/env python3
"""Import the release identity into an isolated, temporary GitHub Actions keychain."""

import base64
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import tempfile

from code_signing import certificate_path, fingerprint, signing_options


def security(*args):
    result = subprocess.run(["/usr/bin/security", *map(str, args)], capture_output=True)
    if result.returncode:
        raise RuntimeError(f"Keychain operation {args[0]} failed ({result.returncode}).")
    return result.stdout.decode("utf-8")


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise RuntimeError("This provisioning script is only for GitHub Actions.")
    signer = fingerprint(certificate_path("distribution"))
    encoded = os.environ.pop("ORBITSHIFT_CERTIFICATE_P12", "")
    password = os.environ.pop("ORBITSHIFT_CERTIFICATE_PASSWORD", "")
    if not encoded or not password:
        raise RuntimeError("Release code-signing secrets are missing.")
    temporary = Path(os.environ["RUNNER_TEMP"])
    keychain = temporary / "OrbitShift-release.keychain-db"
    if keychain.exists() or keychain.is_symlink():
        raise RuntimeError("Refusing to overwrite an existing signing keychain.")
    os.umask(0o077)
    keychain_password = secrets.token_urlsafe(32)
    created = False
    try:
        security("create-keychain", "-p", keychain_password, keychain)
        created = True
        security("set-keychain-settings", "-lut", "21600", keychain)
        security("unlock-keychain", "-p", keychain_password, keychain)
        with tempfile.TemporaryDirectory(prefix="OrbitShift-certificate-", dir=temporary) as directory:
            archive = Path(directory) / "identity.p12"
            archive.write_bytes(base64.b64decode(encoded, validate=True))
            security("import", archive, "-k", keychain, "-P", password, "-T", "/usr/bin/codesign")
        security("set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", keychain_password, keychain)
        # --keychain narrows identity lookup, but codesign still uses the user's
        # search list for the certificate chain. A clean runner has no login copy.
        search_list = shlex.split(security("list-keychains", "-d", "user"))
        if str(keychain) not in search_list:
            security("list-keychains", "-d", "user", "-s", *search_list, keychain)
        os.environ["ORBITSHIFT_SIGNING_IDENTITY"] = signer
        os.environ["ORBITSHIFT_SIGNING_KEYCHAIN"] = str(keychain)
        signing_options("distribution")
        with Path(os.environ["GITHUB_ENV"]).open("a") as stream:
            stream.write(f"ORBITSHIFT_SIGNING_IDENTITY={signer}\nORBITSHIFT_SIGNING_KEYCHAIN={keychain}\n")
        print("Imported the pinned release identity into the temporary signing keychain.")
    except BaseException:
        if created:
            security("delete-keychain", keychain)
        raise


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error))
