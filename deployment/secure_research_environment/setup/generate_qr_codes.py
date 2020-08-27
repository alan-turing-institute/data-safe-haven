#!/usr/bin/env python3
from pathlib import Path
import re
from subprocess import run

# Read username and TOTP hash combinations
totp_hashes = open("./totp_hashes.txt", "r").readlines()
totp_hashes = [line.split() for line in totp_hashes]

# Create QR code directory
base_directory = Path(__file__).parent.absolute()
qr_directory = base_directory / "qr"
qr_directory.mkdir(exist_ok=True)

for username, totp_hash in totp_hashes:
    # Find the base32 secret for each user
    result = run(["oathtool", "--totp", "-v", totp_hash],
                 capture_output=True, text=True)
    base32_secret = re.search(
        r"^Base32 secret: ([A-Z0-9]{24})$", result.stdout,
        re.MULTILINE
    ).group(1)

    # Generate a QR code for each user
    result = run(["qrencode",
                  f"otpauth://totp/{username}@tier1vm?secret={base32_secret}",
                  "-o",
                  f"{qr_directory}/{username}.png"])

    if result.returncode == 0:
        print(f"Successfully generated QR code for user {username}")
    else:
        print(f"Failed to generate QR code for user {username}")

print(f"QR code files are located in {qr_directory}")
