from django.contrib.auth.models import AbstractUser
from django.db import models

from projects.models import Project

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
    project = models.ForeignKey(Project, on_delete=models.CASCADE)
