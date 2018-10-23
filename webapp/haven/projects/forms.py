from braces.forms import UserKwargModelFormMixin
from django import forms

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
