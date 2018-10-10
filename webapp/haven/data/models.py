from datetime import datetime

from django.db import models

from .tiers import Tier, TIERS


class Dataset(models.Model):
    name = models.CharField(max_length=256)
    description = models.TextField()
    created_at = models.DateTimeField(default=datetime.now)

    tier = models.PositiveSmallIntegerField(
        default=Tier.THREE,
        choices=TIERS,
    )
