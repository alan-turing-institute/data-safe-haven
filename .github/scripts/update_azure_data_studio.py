#! /usr/bin/env python3
from lxml import html
import hashlib
import requests

remote_page = requests.get("https://docs.microsoft.com/en-us/sql/azure-data-studio/download-azure-data-studio", allow_redirects=True)
root = html.fromstring(remote_page.content)
short_link = root.xpath("//a[contains(text(), '.deb')]/@href")[0]

remote_content = requests.get(short_link, allow_redirects=True)
sha256 = hashlib.sha256(remote_content.content).hexdigest()
version = remote_content.url.split("-")[-1].replace(".deb", "")
remote = "/".join(remote_content.url.split("/")[:-1] + ["|DEBFILE|"])

with open("deployment/secure_research_desktop/packages/deb-azuredatastudio.version", "w") as f_out:
    f_out.write(f"hash: {sha256}\n")
    f_out.write(f"version: {version}\n")
    f_out.write("debfile: azuredatastudio-linux-|VERSION|.deb\n")
    f_out.write(f"remote: {remote}\n")
