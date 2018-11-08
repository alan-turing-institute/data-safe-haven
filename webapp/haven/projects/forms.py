from braces.forms import UserKwargModelFormMixin
from django import forms
from django.core.exceptions import ValidationError

from .models import Project
from .roles import ProjectRole


class ProjectForm(UserKwargModelFormMixin, forms.ModelForm):
    class Meta:
        model = Project
        fields = ['name', 'description']

    def save(self, **kwargs):
        project = super().save(commit=False)
        project.created_by = self.user
        project.save()
        self.save_m2m()
        return project


class ProjectAddUserForm(UserKwargModelFormMixin, forms.Form):
    username = forms.CharField(help_text='Username')
    role = forms.ChoiceField(
        choices=ProjectRole.choices(),
        help_text='Role on this project'
    )

    def clean_username(self):
        username = self.cleaned_data['username']

        if self.project.participant_set.filter(
            user__username=username
        ).exists():
            raise ValidationError("User is already on project")
        return username

    def save(self, **kwargs):
        role = self.cleaned_data['role']
        username = self.cleaned_data['username']
        return self.project.add_user(username, role, self.user)
