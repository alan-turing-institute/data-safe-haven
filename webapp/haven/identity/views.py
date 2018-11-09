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
        user_role = self.request.user.user_role

        form.fields['role'].choices = [
            (role, name)
            for (role, name) in form.fields['role'].choices
            if user_role.can_create(UserRole(role))
        ]

    def get_form(self):
        form = super().get_form()
        self._restrict_roles(form)
        return form
