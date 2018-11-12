from braces.views import UserFormKwargsMixin
from django.contrib.auth.mixins import LoginRequiredMixin
from django.views.generic.edit import CreateView

from core.forms import InlineFormSetHelper
from projects.forms import AddUsersToProjectInlineFormSet

from .forms import CreateUserForm
from .mixins import UserRoleRequiredMixin
from .models import User
from .roles import UserRole


class UserCreate(LoginRequiredMixin, UserFormKwargsMixin, UserRoleRequiredMixin, CreateView):
    form_class = CreateUserForm
    model = User
    success_url = '/'

    user_roles = [UserRole.SYSTEM_CONTROLLER]

    def get_context_data(self, **kwargs):
        kwargs['formset'] = self.get_formset()
        kwargs['helper'] = InlineFormSetHelper()
        return super().get_context_data(**kwargs)

    def get_formset(self, **kwargs):
        form_kwargs = {'user': self.request.user}
        if self.request.method == 'POST':
            return AddUsersToProjectInlineFormSet(self.request.POST, form_kwargs=form_kwargs)
        else:
            return AddUsersToProjectInlineFormSet(form_kwargs=form_kwargs)

    def post(self, request, *args, **kwargs):
        formset = self.get_formset()
        form = self.get_form()
        if form.is_valid() and formset.is_valid():
            formset.instance = form.save()
            formset.save()
            return self.form_valid(form)
        else:
            return self.form_invalid(form)
