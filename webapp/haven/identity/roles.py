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
            return [
                self.SYSTEM_CONTROLLER,
                self.RESEARCH_COORDINATOR,
                self.DATA_PROVIDER_REPRESENTATIVE,
            ]
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
