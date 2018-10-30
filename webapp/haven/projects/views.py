from braces.views import UserFormKwargsMixin
from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import Q
from django.views.generic import ListView
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
        qs = super().get_queryset()
        view_all = (
            self.request.user.is_superuser or
            self.request.user.role == UserRole.SYSTEM_CONTROLLER
        )

        if not view_all:
            qs = qs.filter(
                Q(created_by=self.request.user) |
                Q(participant__user=self.request.user)
            )
        return qs
