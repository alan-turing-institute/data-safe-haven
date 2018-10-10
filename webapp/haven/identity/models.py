from django.contrib.auth.models import AbstractUser
from django.db import models

from projects.models import Project

from .roles import CREATION_PERMISSIONS, GLOBAL_ROLES, PROJECT_ROLES


class User(AbstractUser):
    role = models.CharField(max_length=50, choices=GLOBAL_ROLES, blank=True)

    def can_create_role(self, role):
        """
        Can this user create another user or participant with the given role?
        """
        return role in CREATION_PERMISSIONS[self.role]


class Participant(models.Model):
    role = models.CharField(max_length=50, choices=PROJECT_ROLES)

    user = models.ForeignKey(User, on_delete=models.CASCADE)
    project = models.ForeignKey(Project, on_delete=models.CASCADE)

    def can_create_role(self, role):
        """
        Can this user create another participant with the given role?
        """
        return role in CREATION_PERMISSIONS[self.role]
