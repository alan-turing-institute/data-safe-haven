import pytest

from identity.models import User
from identity.roles import UserRole


DUMMY_PASSWORD = 'password'


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
        username='participant',
        email='coordinator@example.com',
        role=UserRole.PROJECT_PARTICIPANT,
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
def as_project_participant(client, project_participant):
    client.login(username=project_participant.username, password=DUMMY_PASSWORD)
    return client
