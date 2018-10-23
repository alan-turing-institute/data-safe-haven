from braces.views import UserFormKwargsMixin
from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic.edit import CreateView

from identity.mixins import UserRoleRequiredMixin
from identity.roles import UserRole

from .forms import ProjectForm


class ProjectCreate(LoginRequiredMixin, UserRoleRequiredMixin, UserFormKwargsMixin, CreateView):
    form_class = ProjectForm
    success_url = '/'

    user_roles = [UserRole.SYSTEM_CONTROLLER, UserRole.RESEARCH_COORDINATOR]
