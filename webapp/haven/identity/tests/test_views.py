import pytest

from core import recipes
from identity.models import User


@pytest.mark.django_db
class TestCreateUser:
    def test_anonymous_cannot_access_page(self, client, helpers):
        response = client.get('/users/new')
        helpers.assert_login_redirect(response)

        response = client.post('/users/new', {})
        helpers.assert_login_redirect(response)
        assert not User.objects.filter(username='testuser@example.com').exists()

    def test_view_page(self, as_system_controller):
        response = as_system_controller.get('/users/new')

        assert response.status_code == 200
        assert response.context['form']
        assert response.context['formset']

    def test_create_user(self, as_system_controller):
        response = as_system_controller.post('/users/new', {
            'email': 'testuser@example.com',
            'first_name': 'Test',
            'last_name': 'User',
            'participant_set-TOTAL_FORMS': 1,
            'participant_set-MAX_NUM_FORMS': 1,
            'participant_set-MIN_NUM_FORMS': 0,
            'participant_set-INITIAL_FORMS': 0,
        }, follow=True)

        assert response.status_code == 200
        assert User.objects.filter(email='testuser@example.com').exists()

    def test_create_user_and_add_to_project(self, as_system_controller):
        project = recipes.project.make()
        response = as_system_controller.post('/users/new', {
            'email': 'testuser@example.com',
            'first_name': 'Test',
            'last_name': 'User',
            'participant_set-TOTAL_FORMS': 1,
            'participant_set-MAX_NUM_FORMS': 1,
            'participant_set-MIN_NUM_FORMS': 0,
            'participant_set-INITIAL_FORMS': 0,
            'participant_set-0-project': project.id,
            'participant_set-0-role': 'researcher',
        }, follow=True)

        assert response.status_code == 200
        assert User.objects.filter(email='testuser@example.com').exists()

    def test_returns_403_if_cannot_create_users(self, as_project_participant):
        response = as_project_participant.get('/users/new')
        assert response.status_code == 403

        response = as_project_participant.post('/users/new', {})
        assert response.status_code == 403
        assert not User.objects.filter(email='testuser@example.com').exists()
