from django.db import models
from django.db.models import Q


class ProjectQuerySet(models.QuerySet):
    def get_visible_projects(self, user):
        if user.user_role.can_view_all_projects:
            return self
        else:
            return self.filter(
                Q(created_by=user) |
                Q(participant__user=user)
            ).distinct()
