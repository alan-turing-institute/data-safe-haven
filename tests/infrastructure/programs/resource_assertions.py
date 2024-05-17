"""Functions for testing Pulumi resources inside an apply loop"""

import json


def assert_equal(target, source):
    try:
        assert source == target
    except AssertionError as exc:
        msg = f"'{source}' {type(source)} and '{target}' {type(target)} are not equal."
        raise ValueError(msg) from exc


def assert_equal_json(target, source):
    json_source = json.dumps(source, sort_keys=True)
    json_target = json.dumps(target, sort_keys=True)
    assert_equal(json_source, json_target)
