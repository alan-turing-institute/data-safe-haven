from enum import Enum


class UserRole(Enum):
    """
    User roles global to the system
    """

    # Roles which are assignable to users on the `role` field
    SYSTEM_CONTROLLER = 'system_controller'
    RESEARCH_COORDINATOR = 'research_coordinator'
    DATA_PROVIDER_REPRESENTATIVE = 'data_provider_representative'

    # Django admin superuser
    SUPERUSER = 'superuser'

    # No user role - this means an unprivileged user who will most likely have
    # roles on individual projects but has no global / system-level role.
    NONE = ''

    @classmethod
    def choices(cls):
        """Dropdown choices for user roles"""
        return [
            (cls.SYSTEM_CONTROLLER.value, 'System Controller'),
            (cls.RESEARCH_COORDINATOR.value, 'Research Coordinator'),
            (cls.DATA_PROVIDER_REPRESENTATIVE.value, 'Data Provider Representative'),
        ]

    @property
    def creatable_roles(self):
        """
        User Roles which this role is allowed to create

        :return: list of `UserRole` objects
        """
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
    def can_view_all_projects(self):
        """Can a user with this role view all projects?"""
        return self in [
            self.SUPERUSER,
            self.SYSTEM_CONTROLLER,
        ]

    @property
    def can_edit_all_projects(self):
        """Can a user with this role edit all projects?"""
        return self in [
            self.SUPERUSER,
            self.SYSTEM_CONTROLLER,
        ]

    @property
    def can_create_projects(self):
        """Can a user with this role create projects?"""
        return self in [
            self.SUPERUSER,
            self.SYSTEM_CONTROLLER,
            self.RESEARCH_COORDINATOR,
        ]

    @property
    def can_create_users(self):
        """Can a user with this role create other users?"""
        return self in [
            self.SUPERUSER,
            self.SYSTEM_CONTROLLER,
            self.RESEARCH_COORDINATOR,
        ]

    def can_create(self, role):
        """
        Can a user with this role create other users with the given role?

        :param role: `UserRole` to be created
        :return `True` if can create role, `False` if not
        """
        return (
            role is self.NONE and self.can_create_users or
            role in self.creatable_roles
        )
