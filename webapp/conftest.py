import pytest

from core import recipes
from identity.models import User
from identity.roles import ProjectRole, UserRole


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
def project_participant():
    return User.objects.create_user(
        username='project_participant',
        email='project_participant@example.com',
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
def investigator():
    return recipes.participant.make(role=ProjectRole.INVESTIGATOR)


@pytest.fixture
def researcher():
    return recipes.participant.make(role=ProjectRole.RESEARCHER)


@pytest.fixture
def as_superuser(client, superuser):
    client.force_login(superuser)
    return client


@pytest.fixture
def as_system_controller(client, system_controller):
    client.force_login(system_controller)
    return client


@pytest.fixture
def as_research_coordinator(client, research_coordinator):
    client.force_login(research_coordinator)
    return client


@pytest.fixture
def as_data_provider_representative(client, data_provider_representative):
    client.force_login(data_provider_representative)
    return client


@pytest.fixture
def as_project_participant(client, project_participant):
    client.force_login(project_participant)
    return client
