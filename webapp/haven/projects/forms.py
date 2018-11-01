from braces.forms import UserKwargModelFormMixin
from django import forms

from identity.roles import ProjectRole

from .models import Project


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


class ProjectAddUserForm(forms.Form):
    username = forms.CharField(help_text='Username')
    role = forms.ChoiceField(
        choices=ProjectRole.CHOICES,
        help_text='Role on this project'
    )
