from braces.views import UserFormKwargsMixin
from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.urls import reverse
from django.views.generic import DetailView, ListView
from django.views.generic.edit import CreateView, FormMixin

from identity.mixins import UserRoleRequiredMixin
from identity.roles import UserRole

from .forms import ProjectAddUserForm, ProjectForm
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


class ProjectAddUser(LoginRequiredMixin, UserPassesTestMixin, FormMixin, DetailView):
    model = Project
    template_name = 'projects/project_add_user.html'
    form_class = ProjectAddUserForm

    def get_form(self):
        form = super().get_form()

        creatable_roles = self.request.user.creatable_roles_for_project(self.get_object())

        form.fields['role'].choices = [
            (role, name)
            for (role, name) in form.fields['role'].choices
            if role in creatable_roles or role == ''
        ]
        return form

    def get_success_url(self):
        obj = self.get_object()
        return reverse('projects:detail', args=[obj.id])

    def get_queryset(self):
        return super().get_queryset().get_visible_projects(self.request.user)

    def test_func(self):
        return self.request.user.can_add_user_to_project(self.get_object())

    def post(self, request, *args, **kwargs):
        form = self.get_form()
        self.object = self.get_object()
        if form.is_valid():
            role = form.cleaned_data['role']
            username = form.cleaned_data['username']

            self.object.add_user(username, role, self.request.user)

            return self.form_valid(form)
        else:
            return self.form_invalid(form)
