#! /usr/bin/env python3
import json
from lxml import html
from natsort import natsorted
import requests


def get_latest_version(url, search_text):
    """
    Get latest version number of a database driver from the Maven repository.

    Fetches the HTML page at the given URL, then converts it to an lxml tree.
    Numeric strings are then extracted.
    Note that mostly numeric strings for some drivers contain non-numeric text,
    as different driver types exist for those drivers, even where the version number is the same.
    The largest (latest) version number of the driver is then returned.

    Parameters
    ----------
    url : str
        The URL of the Maven repository containing the driver
    search_text : str
        Text to search for in the repository, to distinguish the driver from other files

    Returns
    -------
    list
        The latest available version number of the driver
    """

    remote_page = requests.get(url, allow_redirects=True)
    root = html.fromstring(remote_page.content)
    return natsorted([v for v in root.xpath("//a[contains(text(), '" + search_text + "')]/@href") if v != "../"])[-1].replace("/", "")


drivers = [
    {
        'name': "mssql_jdbc",
        'url': "https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/",
        'search_text': "jre8/"
    },
    {
        'name': "pgjdbc",
        'url': "https://repo1.maven.org/maven2/org/postgresql/pgjdbc-versions/",
        'search_text': "/"
    },
    {
        'name': "postgresql",
        'url': "https://repo1.maven.org/maven2/org/postgresql/postgresql/",
        'search_text': "/"
    },
    {
        'name': "postgis_geometry",
        'url': "https://repo1.maven.org/maven2/net/postgis/postgis-geometry/",
        'search_text': "/"
    },
    {
        'name': "postgis_jdbc",
        'url': "https://repo1.maven.org/maven2/net/postgis/postgis-jdbc/",
        'search_text': "/"
    },
    {
        'name': "waffle_jna",
        'url': "https://repo1.maven.org/maven2/com/github/waffle/waffle-jna/",
        'search_text': "/"
    }
]

output = {driver['name']: get_latest_version(driver['url'], driver['search_text']) for driver in drivers}

with open("deployment/secure_research_desktop/packages/dbeaver-driver-versions.json", "w") as f_out:
    f_out.writelines(json.dumps(output, indent=4, sort_keys=True))
