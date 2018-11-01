import pytest

from core import recipes
from identity.roles import ProjectRole


@pytest.mark.django_db
class TestProject:
    def test_role_in_project(self, researcher):
        assert researcher.project.user_role(researcher.user) == ProjectRole.RESEARCHER

    def test_role_in_project_returns_None_if_no_role(self, project_participant):
        project = recipes.project.make()

        assert project.user_role(project_participant) is None
