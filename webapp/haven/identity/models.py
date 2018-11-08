from django.contrib.auth.models import AbstractUser
from django.db import models

from projects.roles import ProjectRole

from .roles import UserRole


class User(AbstractUser):
    """
    Represents a user that can log in to the system
    """
    role = models.CharField(
        max_length=50,
        choices=UserRole.choices(),
        blank=True,
        help_text="The user's role in the system"
    )

    # No created_at field here since `AbstractUser` already stores this
    created_by = models.ForeignKey(
        'self',
        on_delete=models.PROTECT,
        null=True,
        related_name='+',
        help_text='User who created this user',
    )

    @property
    def user_role(self):
        if self.is_superuser:
            return UserRole.SUPERUSER
        return UserRole(self.role)

    def get_participant(self, project):
        """
        Return a Participant object for a user on the project

        :return: `Participant` object or None if user is not involved in project
        """
        from projects.models import Participant
        try:
            return self.participant_set.get(project=project)
        except Participant.DoesNotExist:
            return None

    def project_role(self, project):
        """
        Return the role of a user on this project

        :return: ProjectRole or None if user is not involved in project
        """
        if ((self.is_superuser or
             self.user_role is UserRole.SYSTEM_CONTROLLER or
             self == project.created_by)):
            return ProjectRole.PROJECT_ADMIN
        else:
            participant = self.get_participant(project)
            return ProjectRole(participant.role) if participant else None
