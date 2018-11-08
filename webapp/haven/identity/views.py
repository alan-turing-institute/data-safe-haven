from braces.views import UserFormKwargsMixin
from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic.edit import CreateView

from .forms import CreateUserForm
from .mixins import UserRoleRequiredMixin
from .models import User
from .roles import UserRole


class UserCreate(LoginRequiredMixin, UserFormKwargsMixin, UserRoleRequiredMixin, CreateView):
    form_class = CreateUserForm
    model = User
    success_url = '/'

    user_roles = [UserRole.SYSTEM_CONTROLLER]

    def _restrict_roles(self, form):
        """
        Ensure role creation is restricted for the user
        """
        creatable_roles = self.request.user.creatable_roles

        form.fields['role'].choices = [
            (role, name)
            for (role, name) in form.fields['role'].choices
            if UserRole(role) in creatable_roles or role == ''
        ]

    def get_form(self):
        form = super().get_form()
        self._restrict_roles(form)
        return form
