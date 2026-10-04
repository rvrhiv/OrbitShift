#!/usr/bin/env python3
"""Keep each OrbitShift channel tied to a persistent code-signing certificate."""

import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def run(*args):
    return subprocess.run([str(arg) for arg in args], check=True, capture_output=True, text=True)


def certificate_path(flavor):
    if flavor == "development":
        return ROOT / ".local-builds/Development-Certificate.pem"
    return ROOT / "Config/Release-Certificate.pem"


def fingerprint(certificate):
    if certificate.is_symlink() or not certificate.is_file():
        raise RuntimeError(f"Missing signing certificate: {certificate}. See docs/releasing.md.")
    output = run("/usr/bin/openssl", "x509", "-in", certificate, "-noout", "-fingerprint", "-sha1").stdout
    value = output.strip().split("=")[-1].replace(":", "").upper()
    if not re.fullmatch(r"[A-F0-9]{40}", value):
        raise RuntimeError("Invalid certificate fingerprint.")
    return value


def identity(flavor):
    override = os.environ.get("ORBITSHIFT_SIGNING_IDENTITY", "").upper()
    if override and not re.fullmatch(r"[A-F0-9]{40}", override):
        raise RuntimeError("ORBITSHIFT_SIGNING_IDENTITY must be a certificate SHA-1 fingerprint.")
    # CI also checks a Dev bundle using its explicitly provisioned release identity.
    if flavor == "development" and override:
        return override
    expected = fingerprint(certificate_path(flavor))
    if override and override != expected:
        raise RuntimeError("The signing identity does not match the pinned channel certificate.")
    return expected


def requirement(flavor, signer):
    bundle_id = "com.rvrhiv.OrbitShift.dev" if flavor == "development" else "com.rvrhiv.OrbitShift"
    return f'identifier "{bundle_id}" and certificate leaf = H"{signer.lower()}"'


def verify(app, flavor, signer=None):
    expected = requirement(flavor, signer or identity(flavor))
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--all-architectures", "-R=" + expected, app)
    result = run("/usr/bin/codesign", "--display", "-r-", app)
    match = re.search(r"^designated => (.+)$", result.stdout + result.stderr, re.MULTILINE)
    if not match or match.group(1) != expected:
        raise RuntimeError("Expected a stable certificate-bound designated requirement.")


def signing_options(flavor):
    signer = identity(flavor)
    keychain = os.environ.get("ORBITSHIFT_SIGNING_KEYCHAIN")
    keychains = [keychain] if keychain else []
    # A self-signed identity is usable without adding it to the trust store.
    # Do not use -v, which filters out identities without Apple/root trust.
    available = run("/usr/bin/security", "find-identity", "-p", "codesigning", *keychains).stdout
    if not re.search(r"\b" + signer + r"\b", available, re.IGNORECASE):
        raise RuntimeError("The persistent signing private key is missing from Keychain. Restore it; do not regenerate it.")
    options = ["--sign", signer, "--timestamp=none"]
    if keychain:
        options += ["--keychain", keychain]
    return signer, options


def sign(app, flavor, signer, options, previous=None):
    if previous:
        existing = run("/usr/bin/codesign", "--display", "--verbose=2", previous)
        if "Signature=adhoc" not in existing.stdout + existing.stderr:
            # The first migration from ad-hoc signing is intentional. Afterwards,
            # refuse a replacement which would invalidate the existing identity.
            verify(previous, flavor, signer)
    run("/usr/bin/codesign", "--force", *options, app)
    verify(app, flavor, signer)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("flavor", choices=["development", "distribution"])
    arguments = parser.parse_args()
    try:
        verify(arguments.app, arguments.flavor)
        print("Code signature matches the persistent channel certificate.")
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
