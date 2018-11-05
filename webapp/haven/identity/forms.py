from braces.forms import UserKwargModelFormMixin
from django import forms
from django.core.exceptions import ValidationError

from .models import User


class CreateUserForm(UserKwargModelFormMixin, forms.ModelForm):
    class Meta:
        model = User
        fields = ['username', 'role']

    def clean_username(self):
        username = self.cleaned_data['username']
        if User.objects.filter(username=username).exists():
            raise ValidationError("Username already exists")
        return username

    def save(self, **kwargs):
        user = super().save(commit=False)
        user.created_by = self.user
        user.save()
        self.save_m2m()
        return user
