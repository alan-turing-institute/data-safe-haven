import pytest

from core import recipes
from identity.roles import ProjectRole, UserRole


@pytest.mark.django_db
class TestUserCreatableRoles:
    def test_superuser_can_create_any_roles(self, superuser):
        assert superuser.creatable_roles == UserRole.ALL

    def test_creatable_roles(self, system_controller):
        assert UserRole.RESEARCH_COORDINATOR in system_controller.creatable_roles
        assert UserRole.SYSTEM_CONTROLLER not in system_controller.creatable_roles

    def test_superuser_can_create_any_role_on_project(self, superuser):
        project = recipes.project.make()
        assert superuser.creatable_roles_for_project(project) == ProjectRole.ALL

    def test_system_controller_can_create_any_role_on_project(self, system_controller):
        project = recipes.project.make()
        assert system_controller.creatable_roles_for_project(project) == ProjectRole.ALL

    def test_research_coordinator_can_create_any_role_on_own_project(self, research_coordinator):
        project = recipes.project.make(created_by=research_coordinator)
        assert research_coordinator.creatable_roles_for_project(project) == ProjectRole.ALL

    def test_research_coordinator_cannot_create_roles_on_other_project(self, research_coordinator):
        project = recipes.project.make()
        assert research_coordinator.creatable_roles_for_project(project) == []

    def test_researcher_cannot_create_roles(self, researcher):
        assert researcher.user.creatable_roles_for_project(researcher.project) == []

    def test_investigator_can_create_researchers(self, investigator):
        roles = investigator.user.creatable_roles_for_project(investigator.project)
        assert ProjectRole.RESEARCHER in roles

    def test_investigator_cannot_create_researchers_on_other_project(self, investigator):
        project = recipes.project.make()
        assert investigator.user.creatable_roles_for_project(project) == []


@pytest.mark.django_db
class TestCreateProjects:
    def test_superuser_can_create_projects(self, superuser):
        assert superuser.can_create_projects

    def test_system_controller_can_create_projects(self, system_controller):
        assert system_controller.can_create_projects

    def test_research_coordinator_can_create_projects(self, research_coordinator):
        assert research_coordinator.can_create_projects

    def test_ordinary_user_cannot_create_projects(self, project_participant):
        assert not project_participant.can_create_projects
