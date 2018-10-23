from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic.edit import CreateView

from identity.mixins import UserRoleRequiredMixin
from identity.roles import UserRole

from .models import Project


class ProjectCreate(LoginRequiredMixin, UserRoleRequiredMixin, CreateView):
    model = Project
    fields = ['name', 'description']
    success_url = '/'

    user_roles = [UserRole.SYSTEM_CONTROLLER, UserRole.RESEARCH_COORDINATOR]
