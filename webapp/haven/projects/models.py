from django.db import models, transaction

from data.models import Dataset
from identity.models import Participant, User

from .managers import ProjectQuerySet


class Project(models.Model):
    name = models.CharField(max_length=256)
    description = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    created_by = models.ForeignKey(User, on_delete=models.PROTECT)

    datasets = models.ManyToManyField(Dataset, related_name='projects', blank=True)

    objects = ProjectQuerySet.as_manager()

    def __str__(self):
        return self.name

    def user_role(self, user):
        """
        Return the role of a user on this project

        :return: ProjectRole string or None if user is not involved in project
        """
        try:
            return self.participant_set.get(user=user).role
        except Participant.DoesNotExist:
            return None

    @transaction.atomic
    def add_user(self, username, role):
        user, _ = User.objects.get_or_create(username=username)

        return Participant.objects.create(
            user=user, role=role, project=self
        )
