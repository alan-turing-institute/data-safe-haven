"""Regression tests for meaningful Mustache YAML template expansion in CI."""

import importlib.util
import json
from pathlib import Path

import pytest
import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = PROJECT_ROOT / ".github/scripts/expand_mustache.py"
SPEC = importlib.util.spec_from_file_location("expand_mustache", SCRIPT)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


def test_repository_templates_expand_with_realistic_fixture_values():
    outputs = module.render_all(PROJECT_ROOT)
    assert len(outputs) == 3
    assert sum(map(len, outputs.values())) == 5
    for path, variants in outputs.items():
        assert path.suffix in (".yaml", ".yml")
        assert all(isinstance(yaml.safe_load(v), dict) for v in variants)
        assert all("{{" not in v for v in variants)


def test_workspace_feature_flag_validates_both_yaml_structures():
    workspace = (
        PROJECT_ROOT
        / "data_safe_haven/resources/workspace/workspace.cloud_init.mustache.yaml"
    )
    with_disk, without_disk = module.render_variants(workspace, PROJECT_ROOT)
    disk_document = yaml.safe_load(with_disk)
    no_disk_document = yaml.safe_load(without_disk)
    assert "disk_setup" in disk_document
    assert "fs_setup" in disk_document
    assert "disk_setup" not in no_disk_document
    assert "fs_setup" not in no_disk_document
    assert "dshsensitivedata.blob.core.windows.net" in with_disk


def test_rendered_adguardhome_lists_are_not_silently_discarded():
    adguard = (
        PROJECT_ROOT / "data_safe_haven/resources/dns_server/AdGuardHome.mustache.yaml"
    )
    with_filters, without_filters = module.render_variants(adguard, PROJECT_ROOT)
    assert "blocked.example" in with_filters
    assert "clamav.net" in with_filters
    assert "blocked.example" not in without_filters
    assert yaml.safe_load(without_filters)["users"][0]["name"] == "operator"


def test_missing_fixture_and_missing_context_variable_fail(tmp_path):
    path = tmp_path / "data_safe_haven/resources/example.mustache.yaml"
    path.parent.mkdir(parents=True)
    path.write_text("name: {{hostname}}\n", encoding="utf-8")
    with pytest.raises(FileNotFoundError, match="lint fixture"):
        module.render_variants(path, tmp_path)

    fixtures = tmp_path / ".github/resources"
    fixtures.mkdir(parents=True)
    (fixtures / "example.mustache.config.json").write_text("{}", encoding="utf-8")
    with pytest.raises(ValueError, match="hostname"):
        module.render_variants(path, tmp_path)


def test_bad_expanded_yaml_fails_validation(tmp_path):
    path = tmp_path / "data_safe_haven/resources/example.mustache.yaml"
    path.parent.mkdir(parents=True)
    path.write_text("items: [{{value}}\n", encoding="utf-8")
    fixtures = tmp_path / ".github/resources"
    fixtures.mkdir(parents=True)
    (fixtures / "example.mustache.config.json").write_text(
        json.dumps({"value": "hello"}), encoding="utf-8"
    )
    with pytest.raises(yaml.YAMLError):
        module.render_variants(path, tmp_path)


def test_in_place_generates_all_variants_only_after_validating_all(tmp_path):
    resources = tmp_path / "data_safe_haven/resources"
    resources.mkdir(parents=True)
    fixtures = tmp_path / ".github/resources"
    fixtures.mkdir(parents=True)

    example = resources / "example.mustache.yaml"
    example.write_text("enabled: {{enabled}}\n", encoding="utf-8")
    config = fixtures / "example.mustache.config.json"
    config.write_text(
        json.dumps([{"enabled": "true"}, {"enabled": "false"}]), encoding="utf-8"
    )
    outputs = module.render_all(tmp_path, in_place=True)
    assert len(outputs[example]) == 2
    assert yaml.safe_load(example.read_text()) == {"enabled": True}
    assert yaml.safe_load(
        (resources / "example.mustache.variant-2.yaml").read_text()
    ) == {"enabled": False}

    invalid = resources / "invalid.mustache.yaml"
    invalid.write_text("secret: {{unknown}}\n", encoding="utf-8")
    before = example.read_text()
    with pytest.raises(FileNotFoundError):
        module.render_all(tmp_path, in_place=True)
    assert example.read_text() == before
