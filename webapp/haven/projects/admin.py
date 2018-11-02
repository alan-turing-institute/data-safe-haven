from django.contrib import admin

from .models import Participant, Project


admin.site.register(Project)
admin.site.register(Participant)
