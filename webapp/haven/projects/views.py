from braces.views import UserFormKwargsMixin
from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic import DetailView, ListView
from django.views.generic.edit import CreateView

from identity.mixins import UserRoleRequiredMixin
from identity.roles import UserRole

from .forms import ProjectForm
from .models import Project


class ProjectCreate(LoginRequiredMixin, UserRoleRequiredMixin, UserFormKwargsMixin, CreateView):
    form_class = ProjectForm
    success_url = '/'
    model = Project

    user_roles = [UserRole.SYSTEM_CONTROLLER, UserRole.RESEARCH_COORDINATOR]


class ProjectList(LoginRequiredMixin, ListView):
    model = Project
    context_object_name = 'projects'

    def get_queryset(self):
        return super().get_queryset().get_visible_projects(self.request.user)


class ProjectDetail(LoginRequiredMixin, DetailView):
    model = Project

    def get_queryset(self):
        return super().get_queryset().get_visible_projects(self.request.user)
