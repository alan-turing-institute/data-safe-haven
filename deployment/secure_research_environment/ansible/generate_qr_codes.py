#!/usr/bin/env python3
from subprocess import run
import re

# Read username and TOTP hash combinations
totp_hashes = open("./totp_hashes.txt", "r").readlines()
totp_hashes = [line.split() for line in totp_hashes]

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
                  f"{username}.png"])

    if result.returncode == 0:
        print(f"Successfully generated QR code for user {username}")
    else:
        print(f"Failed to generate QR code for user {username}")
