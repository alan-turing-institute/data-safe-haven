import pytest

from core import recipes
from projects.models import Project


@pytest.mark.django_db
class TestCreateProject:
    def test_anonymous_cannot_access_page(self, client, helpers):
        response = client.get('/projects/new')
        helpers.assert_login_redirect(response)

    def test_anonymous_cannot_post_form(self, client, helpers):
        response = client.post('/projects/new')
        helpers.assert_login_redirect(response)

    def test_project_participant_cannot_access_page(self, as_project_participant):
        response = as_project_participant.get('/projects/new')
        assert response.status_code == 403

    def test_project_participant_cannot_post_form(self, as_project_participant):
        response = as_project_participant.post('/projects/new')
        assert response.status_code == 403

    def test_create_project(self, as_research_coordinator):
        response = as_research_coordinator.post(
            '/projects/new',
            {'name': 'my project', 'description': 'a new project'},
            follow=True
        )

        assert response.status_code == 200

        project = Project.objects.get()
        assert project.name == 'my project'
        assert project.description == 'a new project'
        assert project.created_by.username == response.context['user'].username

    def test_create_project_as_system_controller(self, as_system_controller):
        response = as_system_controller.post(
            '/projects/new',
            {'name': 'my project', 'description': 'a new project'},
            follow=True
        )

        assert response.status_code == 200
        assert Project.objects.exists()

    def test_create_project_as_superuser(self, as_superuser):
        response = as_superuser.post(
            '/projects/new',
            {'name': 'my project', 'description': 'a new project'},
            follow=True
        )

        assert response.status_code == 200
        assert Project.objects.exists()


@pytest.mark.django_db
class TestListProjects:
    def test_anonymous_cannot_access_page(self, client, helpers):
        response = client.get('/projects/')
        helpers.assert_login_redirect(response)

    def test_list_owned_projects(self, client, research_coordinator, system_controller):
        my_project = recipes.project.make(created_by=research_coordinator)
        recipes.project.make(created_by=system_controller)
        client.force_login(research_coordinator)
        response = client.get('/projects/')
        assert list(response.context['projects']) == [my_project]

    def test_list_involved_projects(self, as_project_participant):
        pass

    def test_list_all_projects(self, client, research_coordinator, system_controller):
        my_project = recipes.project.make(created_by=system_controller)
        other_project = recipes.project.make(created_by=research_coordinator)
        client.force_login(system_controller)
        response = client.get('/projects/')
        assert list(response.context['projects']) == [my_project, other_project]
