#!/usr/bin/env python3
"""Create or reuse a persistent local signing identity; never rotate an existing channel."""

import argparse
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile

from code_signing import certificate_path, fingerprint, signing_options


def command(*args, sensitive=False, allowed=(0,)):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True)
    if result.returncode not in allowed:
        # Some commands contain temporary passwords. Never include their argv/output.
        detail = "" if sensitive else f": {result.stderr.strip()}"
        raise RuntimeError(f"{Path(args[0]).name} {args[1]} failed ({result.returncode}){detail}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("flavor", nargs="?", default="development", choices=["development", "distribution"])
    args = parser.parse_args()
    if os.environ.get("ORBITSHIFT_SIGNING_IDENTITY") or os.environ.get("ORBITSHIFT_SIGNING_KEYCHAIN"):
        raise RuntimeError("Run local setup without CI signing overrides.")
    destination = certificate_path(args.flavor)
    if destination.exists() or destination.is_symlink():
        signer, _ = signing_options(args.flavor)
        print(f"Reusing {args.flavor} certificate: {signer}")
        return
    label = "OrbitShift Development" if args.flavor == "development" else "OrbitShift Release"
    os.umask(0o077)
    keychain = command("/usr/bin/security", "default-keychain", "-d", "user").strip().strip('"')
    certificates = command("/usr/bin/security", "find-certificate", "-a", "-c", label, "-p", keychain, allowed=(0, 44))
    with tempfile.TemporaryDirectory(prefix="OrbitShift-signing-") as temporary:
        folder = Path(temporary)
        certificate = folder / "certificate.pem"
        if certificates.strip():
            if certificates.count("-----BEGIN CERTIFICATE-----") != 1:
                raise RuntimeError(f"Multiple certificates match {label}; restore the intended certificate explicitly.")
            certificate.write_text(certificates)
        else:
            config = folder / "openssl.cnf"
            config.write_text(
                "[req]\ndistinguished_name=subject\nx509_extensions=codesign\nprompt=no\n"
                f"[subject]\nCN={label}\n[codesign]\nbasicConstraints=critical,CA:FALSE\n"
                "keyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nsubjectKeyIdentifier=hash\n"
            )
            private_key = folder / "private.pem"
            command("/usr/bin/openssl", "req", "-new", "-x509", "-newkey", "rsa:3072", "-nodes", "-sha256",
                    "-days", "3650", "-config", config, "-keyout", private_key, "-out", certificate, sensitive=True)
            password = secrets.token_urlsafe(32)
            password_file = folder / "password"
            password_file.write_text(password)
            archive = folder / "identity.p12"
            command("/usr/bin/openssl", "pkcs12", "-export", "-inkey", private_key, "-in", certificate,
                    "-out", archive, "-passout", f"file:{password_file}", "-keypbe", "PBE-SHA1-3DES",
                    "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1", sensitive=True)
            command("/usr/bin/security", "import", archive, "-k", keychain, "-P", password,
                    "-T", "/usr/bin/codesign", sensitive=True)
        signer = fingerprint(certificate)
        available = command("/usr/bin/security", "find-identity", "-p", "codesigning", keychain)
        if not re.search(r"\b" + signer + r"\b", available, re.IGNORECASE):
            raise RuntimeError("Certificate exists, but its private key is missing. Restore the key instead of replacing it.")
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("x") as stream:
            stream.write(certificate.read_text())
        destination.chmod(0o644)
    print(f"Pinned {args.flavor} certificate: {signer}")
    print("The private key stays in your login Keychain. Keep a secure backup; future builds must use the same key.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError) as error:
        raise SystemExit(str(error))
