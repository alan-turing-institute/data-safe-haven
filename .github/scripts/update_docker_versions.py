#! /usr/bin/env python3

import pathlib
import re
from contextlib import suppress

import requests
from packaging import version


def get_dockerhub_versions(image_details: str) -> tuple[str, str, list[str]]:
    """Get versions for DockerHub images (via API)"""
    image_name, version = image_details.split(":")
    if "/" in image_name:
        namespace, image_name = image_name.split("/")
    else:
        namespace = "library"
    response = requests.get(
        f"https://registry.hub.docker.com/v2/repositories/{namespace}/{image_name}/tags?page_size=1000",
        timeout=60,
    )
    versions = [result["name"] for result in response.json()["results"]]
    return (image_name, version, versions)


def get_github_versions(image_details: str) -> tuple[str, str, list[str]]:
    """Get versions for GitHub images (via manual scraping)"""
    _, organisation, image_name, version = re.split("[:/]", image_details)
    response = requests.get(
        f"https://github.com/{organisation}/{image_name}/pkgs/container/{image_name}/versions",
        timeout=60,
    )
    versions = [
        re.search(r"tag=([^\"]+)\"", line).group(1)
        for line in response.content.decode("utf-8").split()
        if "tag=" in line
    ]
    return (image_name, version, versions)


def get_quayio_versions(image_details: str) -> tuple[str, str, list[str]]:
    """Get versions for Quay.IO images (via API)"""
    _, organisation, image_name, version = re.split("[:/]", image_details)
    response = requests.get(
        f"https://quay.io/api/v1/repository/{organisation}/{image_name}?includeTags=true",
        timeout=60,
    )
    versions = list(response.json()["tags"].keys())
    return (image_name, version, versions)


def annotate(
    versions: list[str], *, stable_only: bool
) -> list[tuple[str, version.Version]]:
    """Annotate a list of potential version strings with the parsed version"""
    annotated = []
    for version_str in versions:
        with suppress(version.InvalidVersion):
            version_ = version.parse(version_str)
            if stable_only and (
                version_.is_devrelease
                or version_.is_prerelease
                or version_.is_postrelease
            ):
                continue
            annotated.append((version_str, version_))
    return annotated


for filename in (pathlib.Path("data_safe_haven") / "infrastructure").glob("**/*.py"):
    needs_replacement = False
    lines = []
    with open(filename) as f_pulumi:
        for line in f_pulumi:
            output = line
            if re.search(r".*image=.*", line):
                image_details = line.split('"')[1]
                if image_details.startswith("ghcr.io"):
                    image, v_current, available = get_github_versions(image_details)
                elif image_details.startswith("quay.io"):
                    image, v_current, available = get_quayio_versions(image_details)
                else:
                    image, v_current, available = get_dockerhub_versions(image_details)
                stable_versions = [v for v in annotate(available, stable_only=True)]
                v_latest = sorted(stable_versions, key=lambda v: v[1], reverse=True)[0][0]
                if v_current != v_latest:
                    print(f"Updating {image} from {v_current} to {v_latest} in {filename}")  # noqa: T201
                    needs_replacement = True
                    output = line.replace(v_current, v_latest)
                else:
                    print(f"Leaving {image} at {v_current} (latest version) in {filename}")  # noqa: T201
            lines += output

    if needs_replacement:
        with open(filename, "w") as f_pulumi:
            f_pulumi.writelines(lines)
