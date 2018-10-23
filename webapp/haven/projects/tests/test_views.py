import pytest

from projects.models import Project


@pytest.mark.django_db
class TestCreateProject:
    def test_anonymous_cannot_access_page(self, client, helpers):
        response = client.get('/projects/new')
        helpers.assert_login_redirect(response)

    def test_anonymous_cannot_post_form(self, client, helpers):
        response = client.post('/projects/new')
        helpers.assert_login_redirect(response)

    def test_regular_user_cannot_access_page(self, as_regular_user):
        response = as_regular_user.get('/projects/new')
        assert response.status_code == 403

    def test_regular_user_cannot_post_form(self, as_regular_user):
        response = as_regular_user.post('/projects/new')
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
