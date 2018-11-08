import pytest

from identity.models import User
from identity.roles import UserRole


@pytest.mark.django_db
class TestCreateUser:
    def test_anonymous_cannot_access_page(self, client, helpers):
        response = client.get('/users/new')
        helpers.assert_login_redirect(response)

        response = client.post('/users/new', {
            'username': 'testuser',
            'role': '',
        })
        helpers.assert_login_redirect(response)
        assert not User.objects.filter(username='testuser').exists()

    def test_view_page(self, as_system_controller):
        response = as_system_controller.get('/users/new')

        assert response.status_code == 200
        assert response.context['form']

    def test_create_user(self, as_system_controller):
        response = as_system_controller.post('/users/new', {
            'username': 'testuser',
            'role': UserRole.RESEARCH_COORDINATOR.value,
        }, follow=True)

        assert response.status_code == 200
        assert User.objects.filter(username='testuser').exists()

    def test_returns_403_if_cannot_create_users(self, as_project_participant):
        response = as_project_participant.get('/users/new')
        assert response.status_code == 403

        response = as_project_participant.post('/users/new', {'username': 'testuser', 'role': ''})
        assert response.status_code == 403
        assert not User.objects.filter(username='testuser').exists()

    def test_restricts_creation_based_on_role(self, as_system_controller):
        # A system controller cannot create a system controller
        response = as_system_controller.post('/users/new', {
            'username': 'controller',
            'role': UserRole.SYSTEM_CONTROLLER.value,
        })

        assert response.status_code == 200
        assert 'role' in response.context['form'].errors
        assert not User.objects.filter(username='testuser').exists()

    def test_roles_are_restricted_in_dropdown(self, as_system_controller):
        response = as_system_controller.get('/users/new')

        assert response.status_code == 200
        role_field = response.context['form']['role'].field
        assert not role_field.valid_value(UserRole.SYSTEM_CONTROLLER.value)
