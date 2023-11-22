from pytest import fixture

from data_safe_haven.config.context_settings import Context


@fixture
def context_dict():
    return {
        "admin_group_id": "d5c5c439-1115-4cb6-ab50-b8e547b6c8dd",
        "location": "uksouth",
        "name": "Acme Deployment",
        "subscription_name": "Data Safe Haven (Acme)",
    }


@fixture
def context(context_dict):
    return Context(**context_dict)
