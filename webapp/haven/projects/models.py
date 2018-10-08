from datetime import datetime

from django.db import models

from data.models import Dataset


class Project(models.Model):
    name = models.CharField(max_length=256)
    description = models.TextField()
    created_at = models.DateTimeField(default=datetime.now)

    datasets = models.ManyToManyField(Dataset, related_name='projects')
