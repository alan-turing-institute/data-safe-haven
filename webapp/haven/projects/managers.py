from django.db import models
from django.db.models import Q

from identity.roles import UserRole


class ProjectQuerySet(models.QuerySet):
    def get_visible_projects(self, user):
        view_all = (
            user.is_superuser or
            user.role == UserRole.SYSTEM_CONTROLLER
        )

        if not view_all:
            return self.filter(
                Q(created_by=user) |
                Q(participant__user=user)
            )

        return self
