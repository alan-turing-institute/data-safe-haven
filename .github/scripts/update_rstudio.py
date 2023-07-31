#! /usr/bin/env python3
from lxml import html
import hashlib
import requests

remote_page = requests.get("https://www.rstudio.com/products/rstudio/download/", allow_redirects=True)
root = html.fromstring(remote_page.content)
short_links = [link for link in root.xpath("//a[contains(text(), '.deb')]/@href") if "debian" not in link]

for ubuntu_version in ["focal", "jammy"]:
    short_link = [link for link in short_links if ubuntu_version in link][0]
    remote_content = requests.get(short_link, allow_redirects=True)
    sha256 = hashlib.sha256(remote_content.content).hexdigest()
    version = "-".join(remote_content.url.split("/")[-1].split("-")[1:-1])
    remote = "/".join(remote_content.url.split("/")[:-1] + ["|DEBFILE|"])

    with open(f"deployment/secure_research_desktop/packages/deb-rstudio-{ubuntu_version}.version", "w") as f_out:
        f_out.write(f"hash: {sha256}\n")
        f_out.write(f"version: {version}\n")
        f_out.write("debfile: rstudio-|VERSION|-amd64.deb\n")
        f_out.write(f"remote: {remote}\n")
