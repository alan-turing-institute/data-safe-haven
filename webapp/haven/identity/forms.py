from django import forms

from .mixins import SaveCreatorMixin
from .models import User


class CreateUserForm(SaveCreatorMixin, forms.ModelForm):
    class Meta:
        model = User
        fields = ['email', 'first_name', 'last_name']

    def save(self, **kwargs):
        self.instance.generate_username()
        return super().save(**kwargs)
