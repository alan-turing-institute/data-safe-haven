from enum import Enum


class ProjectRole(Enum):
    """
    Roles which a user can take in the context of a project.
    """

    # Project admin is an inherited role - it's not stored anywhere but is
    # automatically applied to a project owner, or users which have certain
    # system-level roles
    PROJECT_ADMIN = 'project_admin'

    # Roles which are assignable to users on a project
    REFEREE = 'referee'
    RESEARCH_COORDINATOR = 'research_coordinator'
    INVESTIGATOR = 'investigator'
    RESEARCHER = 'researcher'

    @classmethod
    def choices(cls):
        """Dropdown choices for project roles"""
        return [
            (cls.REFEREE.value, 'Referee'),
            (cls.RESEARCH_COORDINATOR.value, 'Research Coordinator'),
            (cls.INVESTIGATOR.value, 'Investigator'),
            (cls.RESEARCHER.value, 'Researcher'),
        ]

    @property
    def assignable_roles(self):
        """
        Roles this role is allowed to assign on the same project

        :return: list of `ProjectRole` objects
        """
        if self is self.PROJECT_ADMIN:
            return [self.RESEARCH_COORDINATOR, self.INVESTIGATOR, self.RESEARCHER]
        elif self is self.RESEARCH_COORDINATOR:
            return [self.RESEARCH_COORDINATOR, self.INVESTIGATOR, self.RESEARCHER]
        elif self is self.INVESTIGATOR:
            return [self.RESEARCHER]
        return []

    @property
    def can_add_participants(self):
        """Is this role able to add new participants to the project?"""
        return self in [
            self.PROJECT_ADMIN,
            self.RESEARCH_COORDINATOR,
            self.INVESTIGATOR,
        ]

    @property
    def can_list_participants(self):
        """Is this role able to list participants?"""
        return self in [
            self.PROJECT_ADMIN,
            self.RESEARCH_COORDINATOR,
            self.INVESTIGATOR,
        ]

    def can_assign_role(self, role):
        """
        Can this role assign the given role on this project?

        :param role: `ProjectRole` to be assigned
        :return `True` if can assign role, `False` if not
        """
        return role in self.assignable_roles
