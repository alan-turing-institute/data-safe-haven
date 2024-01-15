#! /usr/bin/env python3
import json
from lxml import html
from natsort import natsorted
import requests

output = {}
remote_page = requests.get("https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/", allow_redirects=True)
root = html.fromstring(remote_page.content)
output["mssql_jdbc"] = natsorted([v for v in root.xpath("//a[contains(text(), 'jre8/')]/@href") if v != "../"])[-1].replace("/", "")

remote_page = requests.get("https://repo1.maven.org/maven2/org/postgresql/pgjdbc-versions/", allow_redirects=True)
root = html.fromstring(remote_page.content)
output["pgjdbc"] = natsorted([v for v in root.xpath("//a[contains(text(), '/')]/@href") if v != "../"])[-1].replace("/", "")

remote_page = requests.get("https://repo1.maven.org/maven2/org/postgresql/postgresql/", allow_redirects=True)
root = html.fromstring(remote_page.content)
output["postgresql"] = natsorted([v for v in root.xpath("//a[contains(text(), '/')]/@href") if v != "../"])[-1].replace("/", "")

remote_page = requests.get("https://repo1.maven.org/maven2/net/postgis/postgis-jdbc/", allow_redirects=True)
root = html.fromstring(remote_page.content)
postgis_jdbc_versions = natsorted([v for v in root.xpath("//a[contains(text(), '/')]/@href") if v != "../"])

remote_page = requests.get("https://repo1.maven.org/maven2/net/postgis/postgis-geometry/", allow_redirects=True)
root = html.fromstring(remote_page.content)
postgis_geometry_versions = natsorted([v for v in root.xpath("//a[contains(text(), '/')]/@href") if v != "../"])

postgis = natsorted(set(postgis_jdbc_versions).intersection(set(postgis_geometry_versions)))[-1].replace("/", "")
output["postgis_geometry"] = postgis
output["postgis_jdbc"] = postgis

remote_page = requests.get("https://repo1.maven.org/maven2/com/github/waffle/waffle-jna/", allow_redirects=True)
root = html.fromstring(remote_page.content)
output["waffle_jna"] = natsorted([v for v in root.xpath("//a[contains(text(), '/')]/@href") if v != "../"])[-1].replace("/", "")

with open("deployment/secure_research_desktop/packages/dbeaver-driver-versions.json", "w") as f_out:
    f_out.writelines(json.dumps(output, indent=4, sort_keys=True))
