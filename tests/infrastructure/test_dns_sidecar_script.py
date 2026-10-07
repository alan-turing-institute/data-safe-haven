"""Integration-style shell tests for the DNS sidecar's Azure CLI behavior."""

import os
import subprocess
from pathlib import Path

import pytest

from data_safe_haven.resources import resources_path

SCRIPT = resources_path / "dns_sidecar" / "init.sh"


@pytest.fixture
def run_dns_sidecar(tmp_path: Path):
    """Use a fake 'az' executable, never real Azure credentials or resources."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    azure_cli = bin_dir / "az"
    azure_cli.write_text(
        """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$MOCK_AZ_CALLS"
if [[ "$1" == "login" ]]; then
    [[ "${MOCK_AZ_LOGIN_FAILURE:-0}" != "1" ]]
    exit $?
fi
if [[ "$1" == "container" && "$2" == "show" ]]; then
    while (( $# )); do
        if [[ "$1" == "--name" ]]; then
            shift
            group="$1"
        elif [[ "$1" == "--query" ]]; then
            shift
            query="$1"
        fi
        shift
    done
    [[ "$group" != "${MOCK_AZ_SHOW_FAILURE:-}" ]] || exit 2
    case "$group" in
        group-running) state="Running"; ip="10.10.0.10" ;;
        group-stopped) state="Stopped"; ip="" ;;
        group-pending) state="Pending"; ip="" ;;
        group-no-ip) state="Running"; ip="" ;;
        group-other) state="Running"; ip="10.10.0.20" ;;
    esac
    case "$query" in
        instanceView.state) printf '%s\\n' "$state" ;;
        ipAddress.ip) printf '%s\\n' "$ip" ;;
        *) exit 3 ;;
    esac
    exit 0
fi
if [[ "$1" == "network" && "$2" == "private-dns" ]]; then
    [[ "${MOCK_AZ_UPDATE_FAILURE:-0}" != "1" ]]
    exit $?
fi
exit 4
""",
        encoding="utf-8",
    )
    azure_cli.chmod(0o755)

    def run(
        groups: str, **overrides: str
    ) -> tuple[subprocess.CompletedProcess, list[str]]:
        calls_path = tmp_path / "calls.txt"
        calls_path.write_text("", encoding="utf-8")
        environment = (
            os.environ
            | {
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "MOCK_AZ_CALLS": str(calls_path),
                "CLIENT_ID": "fake-client",
                "RESOURCE_GROUP": "fake-resource-group",
                "SUBSCRIPTION_ID": "fake-subscription",
                "PRIVATE_ZONE_NAME": "private.example.org",
                "RECORD_NAMES_CONTAINER_GROUPS": groups,
            }
            | overrides
        )
        result = subprocess.run(
            ["/bin/bash", str(SCRIPT)],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        return result, calls_path.read_text(encoding="utf-8").splitlines()

    return run


def _dns_updates(calls: list[str]) -> list[str]:
    return [call for call in calls if call.startswith("network private-dns ")]


def test_stopped_group_is_skipped_and_following_running_group_is_updated(
    run_dns_sidecar,
):
    result, calls = run_dns_sidecar("stopped group-stopped,running group-running")
    assert result.returncode == 0
    assert "Skipping container group group-stopped (state: Stopped)" in result.stdout
    updates = _dns_updates(calls)
    assert len(updates) == 1
    assert "--name running" in updates[0]
    assert "aRecords[0].ipv4Address=10.10.0.10" in updates[0]
    assert not any("ipAddress.ip" in call and "group-stopped" in call for call in calls)


@pytest.mark.parametrize("state_group", ["group-stopped", "group-pending"])
def test_nonrunning_groups_do_not_change_dns(run_dns_sidecar, state_group):
    result, calls = run_dns_sidecar(f"skipped {state_group}")
    assert result.returncode == 0
    assert not _dns_updates(calls)


def test_running_group_without_ip_is_skipped(run_dns_sidecar):
    result, calls = run_dns_sidecar("empty group-no-ip,healthy group-other")
    assert result.returncode == 0
    assert "no private IP available" in result.stdout
    updates = _dns_updates(calls)
    assert len(updates) == 1
    assert "--name healthy" in updates[0]


def test_all_running_groups_are_updated(run_dns_sidecar):
    result, calls = run_dns_sidecar("first group-running,second group-other")
    assert result.returncode == 0
    assert len(_dns_updates(calls)) == 2


def test_azure_state_lookup_errors_still_fail(run_dns_sidecar):
    result, calls = run_dns_sidecar(
        "broken group-other,healthy group-running",
        MOCK_AZ_SHOW_FAILURE="group-other",
    )
    assert result.returncode != 0
    assert "Could not check state" in result.stdout
    assert not _dns_updates(calls)


def test_failed_dns_update_is_reported(run_dns_sidecar):
    result, calls = run_dns_sidecar(
        "broken group-running",
        MOCK_AZ_UPDATE_FAILURE="1",
    )
    assert result.returncode != 0
    assert len(_dns_updates(calls)) == 1


def test_failed_azure_login_exits_before_lookups(run_dns_sidecar):
    result, calls = run_dns_sidecar(
        "healthy group-running",
        MOCK_AZ_LOGIN_FAILURE="1",
    )
    assert result.returncode != 0
    assert len(calls) == 1
    assert not _dns_updates(calls)
