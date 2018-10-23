import pytest

from identity.models import User
from identity.roles import UserRole


@pytest.mark.django_db
class TestCreateUser:
    def test_anonymous_cannot_access_page(self, client, helpers):
        response = client.get('/users/new')

        helpers.assert_login_redirect(response)

    def test_anonymous_cannot_post_form(self, client, helpers):
        response = client.post('/users/new', {
            'username': 'testuser',
            'role': '',
        })

        helpers.assert_login_redirect(response)
        assert not User.objects.filter(username='testuser').exists()

    def test_research_coordinator_cannot_access_page(self, as_research_coordinator):
        response = as_research_coordinator.get('/users/new')
        assert response.status_code == 403

    def test_research_coordinator_cannot_post_form(self, as_research_coordinator):
        response = as_research_coordinator.post('/users/new', {'username': 'testuser', 'role': ''})
        assert response.status_code == 403
        assert not User.objects.filter(username='testuser').exists()

    @pytest.mark.parametrize('role', [
        UserRole.SYSTEM_CONTROLLER,
        UserRole.RESEARCH_COORDINATOR,
        UserRole.DATA_PROVIDER_REPRESENTATIVE,
        ''
    ])
    def test_superuser_can_create_users(self, as_superuser, role):
        response = as_superuser.post('/users/new', {
            'username': 'testuser',
            'role': role,
        }, follow=True)

        assert response.status_code == 200
        assert User.objects.filter(username='testuser').exists()

    @pytest.mark.parametrize('role', [
        UserRole.RESEARCH_COORDINATOR,
        UserRole.DATA_PROVIDER_REPRESENTATIVE,
        ''
    ])
    def test_system_controller_can_create_users(self, as_system_controller, role):
        response = as_system_controller.post('/users/new', {
            'username': 'testuser',
            'role': role,
        }, follow=True)

        assert response.status_code == 200
        assert User.objects.filter(username='testuser').exists()

    def test_system_controller_cannot_create_system_controller(self, as_system_controller):
        # A system controller cannot create a system controller
        response = as_system_controller.post('/users/new', {
            'username': 'controller',
            'role': UserRole.SYSTEM_CONTROLLER,
        })

        assert response.status_code == 200
        assert 'role' in response.context['form'].errors
        assert not User.objects.filter(username='testuser').exists()

    def test_roles_are_restricted_in_dropdown(self, as_system_controller):
        response = as_system_controller.get('/users/new', {})

        assert response.status_code == 200
        role_field = response.context['form']['role'].field
        assert not role_field.valid_value(UserRole.SYSTEM_CONTROLLER)
