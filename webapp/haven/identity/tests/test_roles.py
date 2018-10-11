from itertools import permutations

import pytest

from identity.roles import ALL_ROLES, Role, can_create


# These are the role creation permissions the system should be allowing
ALLOWED_CREATIONS = {
    (Role.SYSTEM_CONTROLLER, Role.RESEARCH_COORDINATOR),
    (Role.SYSTEM_CONTROLLER, Role.DATA_PROVIDER_REPRESENTATIVE),
    (Role.SYSTEM_CONTROLLER, Role.REFEREE),
    (Role.SYSTEM_CONTROLLER, Role.INVESTIGATOR),
    (Role.SYSTEM_CONTROLLER, Role.RESEARCHER),

    (Role.RESEARCH_COORDINATOR, Role.REFEREE),
    (Role.RESEARCH_COORDINATOR, Role.INVESTIGATOR),
    (Role.RESEARCH_COORDINATOR, Role.RESEARCHER),

    (Role.INVESTIGATOR, Role.RESEARCHER),
}


# Everything else should be disallowed
DISALLOWED_CREATIONS = set(permutations(ALL_ROLES, 2)) - ALLOWED_CREATIONS


@pytest.mark.parametrize('role1, role2', ALLOWED_CREATIONS)
def test_can_create(role1, role2):
    assert can_create(role1, role2)


@pytest.mark.parametrize('role1, role2', DISALLOWED_CREATIONS)
def test_cannot_create(role1, role2):
    assert not can_create(role1, role2)
