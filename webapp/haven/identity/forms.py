from braces.forms import UserKwargModelFormMixin
from django import forms

from .models import User


class CreateUserForm(UserKwargModelFormMixin, forms.ModelForm):
    class Meta:
        model = User
        fields = ['username', 'role']

    def save(self, **kwargs):
        user = super().save(commit=False)
        user.created_by = self.user
        user.save()
        self.save_m2m()
        return user
