import pytest

from identity.forms import CreateUserForm
from identity.models import User
from identity.roles import UserRole


@pytest.mark.django_db
class TestCreateUserForm:
    def test_create_user(self, system_controller):
        form = CreateUserForm({
            'username': 'testuser',
            'role': UserRole.RESEARCH_COORDINATOR.value,
        }, user=system_controller)
        assert form.is_valid()

        form_user = form.save()

        user = User.objects.get(username='testuser')
        assert user == form_user
        assert user.created_by == system_controller

    def test_cannot_create_user_twice(self, system_controller):
        User.objects.create_user(username='testuser')
        form = CreateUserForm({
            'username': 'testuser',
            'role': UserRole.RESEARCH_COORDINATOR,
        }, user=system_controller)

        assert not form.is_valid()
        assert 'username' in form.errors
