from collections import defaultdict


class Role:
    """
    Define roles that can be taken on by a user, either globally
    or in the context of a project
    """
    SYSTEM_CONTROLLER = 'system_controller'
    RESEARCH_COORDINATOR = 'research_coordinator'
    DATA_PROVIDER_REPRESENTATIVE = 'data_provider_representative'
    REFEREE = 'referee'
    INVESTIGATOR = 'investigator'
    RESEARCHER = 'researcher'

    NAMES = {
        SYSTEM_CONTROLLER: 'System Controller',
        RESEARCH_COORDINATOR: 'Research Coordinator',
        DATA_PROVIDER_REPRESENTATIVE: 'Data Provider Representative',
        RESEARCH_COORDINATOR: 'Research Coordinator',
        REFEREE: 'Referee',
        INVESTIGATOR: 'Investigator',
        RESEARCHER: 'Researcher',
    }


# A list of all roles
ALL_ROLES = [
    Role.SYSTEM_CONTROLLER,
    Role.RESEARCH_COORDINATOR,
    Role.DATA_PROVIDER_REPRESENTATIVE,
    Role.REFEREE,
    Role.INVESTIGATOR,
    Role.RESEARCH_COORDINATOR,
]

# Roles that can be applied globally to a user
GLOBAL_ROLES = [
    Role.SYSTEM_CONTROLLER,
    Role.RESEARCH_COORDINATOR,
]

GLOBAL_ROLE_CHOICES = (
    (role, Role.NAMES[role]) for role in GLOBAL_ROLES
)


# Roles that are project-specific.
PROJECT_ROLES = (
    Role.DATA_PROVIDER_REPRESENTATIVE,
    Role.RESEARCH_COORDINATOR,
    Role.REFEREE,
    Role.INVESTIGATOR,
    Role.RESEARCHER,
)

PROJECT_ROLE_CHOICES = (
    (role, Role.NAMES[role]) for role in PROJECT_ROLES
)


# Mapping of roles to a list of other roles they are allowed to create
CREATION_PERMISSIONS = defaultdict(list, {
    Role.SYSTEM_CONTROLLER: [
        Role.RESEARCH_COORDINATOR,
        Role.DATA_PROVIDER_REPRESENTATIVE,
        Role.REFEREE,
        Role.INVESTIGATOR,
        Role.RESEARCHER,
    ],
    Role.RESEARCH_COORDINATOR: [
        Role.REFEREE,
        Role.INVESTIGATOR,
        Role.RESEARCHER,
    ],
    Role.INVESTIGATOR: [
        Role.RESEARCHER,
    ],
})


def can_create(creator, createe):
    """
    Does the `creator` role have permission to create the `createe` role?

    :param creator: `Role` string representing creator role
    :param createe: `Role` string representing createe role

    :return `True` if creator can create createe, `False` if not
    """
    return createe in CREATION_PERMISSIONS[creator]
