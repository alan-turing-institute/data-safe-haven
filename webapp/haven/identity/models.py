from django.contrib.auth.models import AbstractUser
from django.db import models

from projects.models import Project

from .roles import GLOBAL_ROLE_CHOICES, PROJECT_ROLE_CHOICES, can_create


class User(AbstractUser):
    """
    Represents a user which can log in to the system
    """
    role = models.CharField(
        max_length=50,
        choices=GLOBAL_ROLE_CHOICES,
        blank=True,
        help_text="The user's role in the system"
    )

    def can_create_role(self, role):
        """
        Can this user create another user or participant with the given role?
        """
        return can_create(self.role, role)


class Participant(models.Model):
    """
    Represents a user's participation in a project
    """
    role = models.CharField(
        max_length=50,
        choices=PROJECT_ROLE_CHOICES,
        help_text="The participant's role on this project"
    )

    user = models.ForeignKey(User, on_delete=models.CASCADE)
    project = models.ForeignKey(Project, on_delete=models.CASCADE)

    def can_create_role(self, role):
        """
        Can this participant create another with the given role?
        """
        return can_create(self.role, role)
