#! /usr/bin/env python3
"""Generate QR codes from TOTP hashes"""
from pathlib import Path
import re
from subprocess import run, PIPE
import argparse


def main():
    """Generate QR codes from TOTP hashes"""
    parser = argparse.ArgumentParser(description="Generate QR codes from TOTP hashes")
    parser.add_argument("--totp-hashes", type=str, help="path to the TOTP hashes")
    parser.add_argument("--qr-codes", type=str, help="path to the QR codes")
    parser.add_argument("--host-name", type=str, help="name of the VM")
    args = parser.parse_args()

    # Read username and TOTP hash combinations
    totp_hashes = open(args.totp_hashes, "r").readlines()
    totp_hashes = [line.split() for line in totp_hashes]

    # Create QR code directory
    qr_directory = Path(args.qr_codes)
    qr_directory.mkdir(parents=True, exist_ok=True)

    for username, totp_hash in totp_hashes:
        # Find the base32 secret for each user
        result = run(
            ["oathtool", "--totp", "-v", totp_hash],
            stdout=PIPE,
            universal_newlines=True,
            check=True,
        )
        base32_secret = re.search(
            r"^Base32 secret: ([A-Z0-9]{24})$", result.stdout, re.MULTILINE
        ).group(1)

        # Generate a QR code for each user
        result = run(
            [
                "qrencode",
                f"otpauth://totp/{username}@{args.host_name}?secret={base32_secret}",
                "-o",
                f"{qr_directory}/{username}.png",
            ],
            check=True,
        )

        if result.returncode == 0:
            print(f"Successfully generated QR code for user {username}")
        else:
            print(f"Failed to generate QR code for user {username}")

    print(f"QR code files are located in {qr_directory}")


if __name__ == "__main__":
    main()
