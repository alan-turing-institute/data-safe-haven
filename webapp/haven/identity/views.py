from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.views.generic.edit import CreateView

from .models import User
from .roles import UserRole


class UserCreate(LoginRequiredMixin, UserPassesTestMixin, CreateView):
    model = User
    fields = ['username', 'role']
    success_url = '/'

    def _restrict_roles(self, form):
        """
        Ensure role creation is restricted for the user
        """
        creatable_roles = UserRole.creatable_roles(self.request.user)

        form.fields['role'].choices = [
            (role, name)
            for (role, name) in form.fields['role'].choices
            if role in creatable_roles
        ]

    def get_form(self):
        form = super().get_form()
        self._restrict_roles(form)
        return form

    def test_func(self):
        return UserRole.can_access_user_creation_page(self.request.user)
