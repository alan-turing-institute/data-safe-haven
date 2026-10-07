"""SRE package repositories must follow the latest security tier."""

import pytest
import yaml
from jinja2 import Environment, StrictUndefined

from data_safe_haven.resources import resources_path

ANSIBLE_ROOT = resources_path / "workspace" / "ansible"
PROXY_TASK = ANSIBLE_ROOT / "tasks/package_proxy.yaml"
PLAYBOOK = ANSIBLE_ROOT / "desired_state.yaml"
PIP_TEMPLATE = ANSIBLE_ROOT / "templates/etc/pip.conf.j2"
R_TEMPLATE = ANSIBLE_ROOT / "templates/etc/R/Rprofile.site.j2"


def render(template_path, *, use_software_repositories):
    environment = Environment(autoescape=True, undefined=StrictUndefined)
    template = environment.from_string(template_path.read_text(encoding="utf-8"))
    return template.render(
        software_repository_hostname="nexus.example.internal",
        use_software_repositories=use_software_repositories,
    )


@pytest.mark.parametrize(
    "restricted,expected_pip,expected_cran",
    [
        (
            True,
            "http://nexus.example.internal/repository/pypi-proxy/simple",
            "http://nexus.example.internal/repository/cran-proxy",
        ),
        (False, "https://pypi.org/simple", "https://cloud.r-project.org"),
    ],
)
def test_package_repositories_match_tier(restricted, expected_pip, expected_cran):
    pip = render(PIP_TEMPLATE, use_software_repositories=restricted)
    cran = render(R_TEMPLATE, use_software_repositories=restricted)

    assert f"index-url = {expected_pip}" in pip
    assert f'r["CRAN"] <- "{expected_cran}"' in cran
    if not restricted:
        assert "nexus.example.internal" not in pip
        assert "nexus.example.internal" not in cran
        assert "trusted-host" not in pip


def test_repository_tasks_run_even_after_downgrading_tier():
    desired = yaml.safe_load(PLAYBOOK.read_text(encoding="utf-8"))
    package_tasks = [
        task
        for task in desired[0]["tasks"]
        if task.get("ansible.builtin.import_tasks") == "tasks/package_proxy.yaml"
    ]
    assert len(package_tasks) == 1
    assert "when" not in package_tasks[0]

    templates = yaml.safe_load(PROXY_TASK.read_text(encoding="utf-8"))
    assert {item["dest"] for item in templates[0]["loop"]} == {
        "/etc/pip.conf",
        "/etc/R/Rprofile.site",
    }


def test_tier_downgrade_replaces_existing_restricted_configuration(tmp_path):
    pip_path = tmp_path / "pip.conf"
    cran_path = tmp_path / "Rprofile.site"

    for restricted in (True, False):
        pip_path.write_text(
            render(PIP_TEMPLATE, use_software_repositories=restricted),
            encoding="utf-8",
        )
        cran_path.write_text(
            render(R_TEMPLATE, use_software_repositories=restricted),
            encoding="utf-8",
        )

    assert "https://pypi.org/simple" in pip_path.read_text(encoding="utf-8")
    assert "https://cloud.r-project.org" in cran_path.read_text(encoding="utf-8")
    assert "nexus.example.internal" not in pip_path.read_text(encoding="utf-8")
    assert "nexus.example.internal" not in cran_path.read_text(encoding="utf-8")
