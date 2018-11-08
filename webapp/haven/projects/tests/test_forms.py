import pytest

from core import recipes
from projects.forms import ProjectAddUserForm
from projects.roles import ProjectRole


@pytest.mark.django_db
class TestProjectAddUserForm:
    def test_add_new_user(self, research_coordinator):
        project = recipes.project.make(created_by=research_coordinator)

        form = ProjectAddUserForm({
            'role': ProjectRole.RESEARCHER.value,
            'username': 'newuser',
        }, user=research_coordinator)
        form.project = project
        assert form.is_valid()

        form_obj = form.save()

        participant = project.participant_set.get()
        assert form_obj == participant
        assert participant.user.username == 'newuser'
        assert participant.role == ProjectRole.RESEARCHER.value
        assert participant.created_by == research_coordinator
        assert participant.user.created_by == research_coordinator

    def test_add_existing_user(self, research_coordinator, project_participant):
        project = recipes.project.make(created_by=research_coordinator)

        form = ProjectAddUserForm({
            'role': ProjectRole.RESEARCHER.value,
            'username': project_participant.username,
        }, user=research_coordinator)
        form.project = project

        assert form.is_valid()

        form.save()
        participant = project.participant_set.get()

        assert participant.user == project_participant

    def test_cannot_add_user_to_project_twice(self, research_coordinator, project_participant):
        project = recipes.project.make(created_by=research_coordinator)

        project.add_user(project_participant, ProjectRole.RESEARCHER, research_coordinator)

        form = ProjectAddUserForm({
            'role': ProjectRole.INVESTIGATOR.value,
            'username': project_participant.username,
        }, user=research_coordinator)
        form.project = project

        assert not form.is_valid()
        assert 'username' in form.errors

        assert project.participant_set.count() == 1
