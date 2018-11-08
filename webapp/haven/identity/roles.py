from collections import defaultdict
from enum import Enum


class UserRole(Enum):
    """
    User roles global to the system
    """
    SUPERUSER = 'superuser'
    SYSTEM_CONTROLLER = 'system_controller'
    RESEARCH_COORDINATOR = 'research_coordinator'
    DATA_PROVIDER_REPRESENTATIVE = 'data_provider_representative'
    NONE = ''

    @classmethod
    def all_roles(cls):
        return [
            val
            for val in cls.__members__.values()
            if val.value != ''
        ]

    @classmethod
    def choices(cls):
        return [
            (cls.SYSTEM_CONTROLLER.value, 'System Controller'),
            (cls.RESEARCH_COORDINATOR.value, 'Research Coordinator'),
            (cls.DATA_PROVIDER_REPRESENTATIVE.value, 'Data Provider Representative'),
        ]

    @property
    def creatable_roles(self):
        """
        User Roles which this role is allowed to create
        """
        # Mapping of user roles to a list of other user roles they are allowed to create
        if self is self.SUPERUSER:
            return self.all_roles()
        elif self is self.SYSTEM_CONTROLLER:
            return [
                self.RESEARCH_COORDINATOR,
                self.DATA_PROVIDER_REPRESENTATIVE,
            ]
        return []

    @property
    def can_create_projects(self):
        """Can this user create projects?"""
        return self in [
            UserRole.SUPERUSER,
            UserRole.SYSTEM_CONTROLLER,
            UserRole.RESEARCH_COORDINATOR,
        ]

    @property
    def can_create_users(self):
        """Can this role create other users at all? """
        return bool(self.creatable_roles)


class ProjectRole:
    """
    Roles which a user can take in the context of a project.
    """
    REFEREE = 'referee'
    INVESTIGATOR = 'investigator'
    RESEARCHER = 'researcher'

    # Roles that are project-specific.
    ALL = (
        REFEREE,
        INVESTIGATOR,
        RESEARCHER,
    )

    CHOICES = [
        (REFEREE, 'Referee'),
        (INVESTIGATOR, 'Investigator'),
        (RESEARCHER, 'Researcher'),
    ]

    ALLOWED_CREATIONS = defaultdict(list, {
        INVESTIGATOR: [
            RESEARCHER,
        ],
    })

    @classmethod
    def can_create(cls, creator, createe):
        """
        Does the `creator` role have permission to create the `createe` role?

        :param creator: `Role` string representing creator role
        :param createe: `Role` string representing role to be created

        :return `True` if creator can create createe, `False` if not
        """
        return createe in cls.ALLOWED_CREATIONS[creator]
