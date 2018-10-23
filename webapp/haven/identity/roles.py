from collections import defaultdict


class UserRole:
    """
    User roles global to the system
    """
    SYSTEM_CONTROLLER = 'system_controller'
    RESEARCH_COORDINATOR = 'research_coordinator'
    DATA_PROVIDER_REPRESENTATIVE = 'data_provider_representative'

    ALL = [
        SYSTEM_CONTROLLER,
        RESEARCH_COORDINATOR,
        DATA_PROVIDER_REPRESENTATIVE,
    ]

    CHOICES = [
        (SYSTEM_CONTROLLER, 'System Controller'),
        (RESEARCH_COORDINATOR, 'Research Coordinator'),
        (DATA_PROVIDER_REPRESENTATIVE, 'Data Provider Representative'),
    ]

    # Mapping of user roles to a list of other user roles they are allowed to create
    ALLOWED_CREATIONS = defaultdict(list, {
        SYSTEM_CONTROLLER: [
            RESEARCH_COORDINATOR,
            DATA_PROVIDER_REPRESENTATIVE,
        ],
    })

    @classmethod
    def can_access_user_creation_page(cls, user):
        return bool(cls.creatable_roles(user))

    @classmethod
    def creatable_roles(cls, user):
        if not user.is_authenticated:
            return []
        elif user.is_superuser:
            return cls.ALL
        else:
            return cls.ALLOWED_CREATIONS[user.role]


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
