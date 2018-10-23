import pytest

from identity.models import User
from identity.roles import UserRole


DUMMY_PASSWORD = 'password'


class Helpers:
    def assert_login_redirect(response):
        assert response.status_code == 302
        assert '/login/' in response.url


@pytest.fixture
def helpers():
    return Helpers


@pytest.fixture
def superuser():
    return User.objects.create_superuser(
        username='admin',
        email='admin@example.com',
        password=DUMMY_PASSWORD,
    )


@pytest.fixture
def system_controller():
    return User.objects.create_user(
        username='controller',
        email='controller@example.com',
        role=UserRole.SYSTEM_CONTROLLER,
        password=DUMMY_PASSWORD,
    )


@pytest.fixture
def research_coordinator():
    return User.objects.create_user(
        username='coordinator',
        email='coordinator@example.com',
        role=UserRole.RESEARCH_COORDINATOR,
        password=DUMMY_PASSWORD,
    )


@pytest.fixture
def regular_user():
    return User.objects.create_user(
        username='regular_user',
        email='regular_user@example.com',
        password=DUMMY_PASSWORD,
    )


@pytest.fixture
def data_provider_representative():
    return User.objects.create_user(
        username='datarep',
        email='datarep@example.com',
        role=UserRole.DATA_PROVIDER_REPRESENTATIVE,
        password=DUMMY_PASSWORD,
    )


@pytest.fixture
def as_superuser(client, superuser):
    client.login(username=superuser.username, password=DUMMY_PASSWORD)
    return client


@pytest.fixture
def as_system_controller(client, system_controller):
    client.login(username=system_controller.username, password=DUMMY_PASSWORD)
    return client


@pytest.fixture
def as_research_coordinator(client, research_coordinator):
    client.login(username=research_coordinator.username, password=DUMMY_PASSWORD)
    return client


@pytest.fixture
def as_data_provider_representative(client, data_provider_representative):
    client.login(username=data_provider_representative.username, password=DUMMY_PASSWORD)
    return client


@pytest.fixture
def as_regular_user(client, regular_user):
    client.login(username=regular_user.username, password=DUMMY_PASSWORD)
    return client
