from braces.forms import UserKwargModelFormMixin
from django import forms
from django.core.exceptions import ValidationError
from django.forms import inlineformset_factory

from identity.mixins import SaveCreatorMixin
from identity.models import User

from .models import Participant, Project
from .roles import ProjectRole


class ProjectForm(SaveCreatorMixin, forms.ModelForm):
    class Meta:
        model = Project
        fields = ['name', 'description']


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


class AddUserToProjectInlineForm(SaveCreatorMixin, forms.ModelForm):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields['project'].queryset = Project.objects.get_editable_projects(self.user)

    class Meta:
        model = Participant
        fields = ('project', 'role')

    def clean(self):
        project = self.cleaned_data['project']
        role = ProjectRole(self.cleaned_data['role'])
        if not self.user.project_role(project).can_assign_role(role):
            raise ValidationError("You cannot assign the role on this project")


AddUsersToProjectInlineFormSet = inlineformset_factory(
    User,
    Participant,
    form=AddUserToProjectInlineForm,
    fk_name='user',
    extra=1
)
