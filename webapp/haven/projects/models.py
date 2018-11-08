from django.db import models, transaction

from data.models import Dataset
from identity.models import User

from .managers import ProjectQuerySet
from .roles import ProjectRole


class Project(models.Model):
    name = models.CharField(max_length=256)
    description = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    created_by = models.ForeignKey(User, on_delete=models.PROTECT)

    datasets = models.ManyToManyField(Dataset, related_name='projects', blank=True)

    objects = ProjectQuerySet.as_manager()

    def __str__(self):
        return self.name

    @transaction.atomic
    def add_user(self, username, role, creator):
        """
        Add user to this project
        Creates user if they do not already exist

        :param username: username of user to add
        :param role: Role user will have on the project
        :param creator: `User` who is doing the adding
        """
        user, _ = User.objects.get_or_create(
            username=username,
            defaults={
                'created_by': creator,
            }
        )

        return Participant.objects.create(
            user=user,
            role=role,
            created_by=creator,
            project=self,
        )


class Participant(models.Model):
    """
    Represents a user's participation in a project
    """
    role = models.CharField(
        max_length=50,
        choices=ProjectRole.choices(),
        help_text="The participant's role on this project"
    )

    user = models.ForeignKey(User, on_delete=models.CASCADE)
    project = models.ForeignKey('projects.Project', on_delete=models.CASCADE)

    created_at = models.DateTimeField(
        auto_now_add=True,
        help_text='Time the user was added to the project',
    )
    created_by = models.ForeignKey(
        User,
        on_delete=models.PROTECT,
        related_name='+',
        help_text='User who added this user to the project',
    )

    class Meta:
        unique_together = ('user', 'project')

    def __str__(self):
        return f'{self.user} ({self.get_role_display()} on {self.project})'
