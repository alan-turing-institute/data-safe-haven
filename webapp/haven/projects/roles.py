from enum import Enum


class ProjectRole(Enum):
    """
    Roles which a user can take in the context of a project.
    """

    PROJECT_ADMIN = 'project_admin'
    REFEREE = 'referee'
    INVESTIGATOR = 'investigator'
    RESEARCHER = 'researcher'

    @classmethod
    def choices(cls):
        return [
            (cls.REFEREE.value, 'Referee'),
            (cls.INVESTIGATOR.value, 'Investigator'),
            (cls.RESEARCHER.value, 'Researcher'),
        ]

    @property
    def creatable_roles(self):
        """
        Roles this role is allowed to create on the same project
        """
        if self is self.PROJECT_ADMIN:
            return [self.INVESTIGATOR, self.RESEARCHER]
        elif self is self.INVESTIGATOR:
            return [self.RESEARCHER]
        return []

    @property
    def can_add_participant(self):
        return bool(self.creatable_roles)

    @property
    def can_list_participants(self):
        return self is self.PROJECT_ADMIN

    def can_add(self, role):
        """
        Does this role have permission to assign the given role to a user

        :param role: `ProjectRole` to be created

        :return `True` if can create role, `False` if not
        """
        return role in self.creatable_roles
