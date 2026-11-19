"""Public function-module categories remain available alongside flat imports."""

from data_safe_haven import functions
from data_safe_haven.functions import (
    alphanumeric,
    current_ip_address,
    network,
    strings,
)


def test_categories_are_explicitly_exported():
    assert "network" in functions.__all__
    assert "strings" in functions.__all__
    assert functions.network is network
    assert functions.strings is strings


def test_category_functions_match_existing_flat_imports():
    assert strings.alphanumeric is alphanumeric
    assert network.current_ip_address is current_ip_address
    assert strings.b64encode("data") == "ZGF0YQ=="


def test_public_export_names_resolve_to_categories_and_flat_aliases():
    exported = {name: getattr(functions, name) for name in functions.__all__}

    assert exported["network"] is network
    assert exported["strings"] is strings
    assert exported["alphanumeric"] is alphanumeric
