from django.contrib.auth.models import AbstractUser
from django.db import models

from .roles import ProjectRole, UserRole


class User(AbstractUser):
    """
    Represents a user that can log in to the system
    """
    role = models.CharField(
        max_length=50,
        choices=UserRole.CHOICES,
        blank=True,
        help_text="The user's role in the system"
    )

    @property
    def can_create_users(self):
        """
        Can this user create other users at all?
        """
        return bool(self.creatable_roles)

    @property
    def can_create_projects(self):
        """
        Can this user create other users at all?
        """
        return self.role in [
            UserRole.SYSTEM_CONTROLLER,
            UserRole.RESEARCH_COORDINATOR,
        ]

    def can_add_user_to_project(self, project):
        return bool(self.creatable_roles_for_project(project))

    @property
    def creatable_roles(self):
        """
        Roles which this user is allowed to create
        """
        if self.is_superuser:
            return UserRole.ALL
        else:
            return UserRole.ALLOWED_CREATIONS[self.role]

    def creatable_roles_for_project(self, project):
        """
        Roles this user is allowed to create on the given project
        """
        if ((self.is_superuser or
             self.role == UserRole.SYSTEM_CONTROLLER or
             project.created_by == self)):
            return ProjectRole.ALL
        else:
            role = project.user_role(self)
            if role:
                return ProjectRole.ALLOWED_CREATIONS[role]

        return []


class Participant(models.Model):
    """
    Represents a user's participation in a project
    """
    role = models.CharField(
        max_length=50,
        choices=ProjectRole.CHOICES,
        help_text="The participant's role on this project"
    )

    user = models.ForeignKey(User, on_delete=models.CASCADE)
    project = models.ForeignKey('projects.Project', on_delete=models.CASCADE)

    def __str__(self):
        return f'{self.user} ({self.get_role_display()} on {self.project})'
