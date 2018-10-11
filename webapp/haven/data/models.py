from django.db import models

from .tiers import TIER_CHOICES, Tier


class Dataset(models.Model):
    name = models.CharField(max_length=256)
    description = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    # Data should be started at the most sensitive tier by default
    # and progressed to lower tiers if appropriate
    tier = models.PositiveSmallIntegerField(
        default=Tier.THREE,
        choices=TIER_CHOICES,
    )
