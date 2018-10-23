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

    @property
    def creatable_roles(self):
        """
        Roles which this user is allowed to create
        """
        if not self.is_authenticated:
            return []
        elif self.is_superuser:
            return UserRole.ALL
        else:
            return UserRole.ALLOWED_CREATIONS[self.role]


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
