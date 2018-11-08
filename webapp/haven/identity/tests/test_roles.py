from identity.roles import UserRole
from projects.roles import ProjectRole


class TestUserRole:
    def test_superuser_can_create_any_roles(self):
        assert UserRole.SYSTEM_CONTROLLER in UserRole.SUPERUSER.creatable_roles
        assert UserRole.RESEARCH_COORDINATOR in UserRole.SUPERUSER.creatable_roles

    def test_creatable_roles(self):
        assert UserRole.RESEARCH_COORDINATOR in UserRole.SYSTEM_CONTROLLER.creatable_roles
        assert UserRole.SYSTEM_CONTROLLER not in UserRole.SYSTEM_CONTROLLER.creatable_roles

    def test_no_creatable_roles(self):
        assert UserRole.RESEARCH_COORDINATOR.creatable_roles == []
        assert UserRole.NONE.creatable_roles == []

    def test_superuser_can_create_projects(self):
        assert UserRole.SUPERUSER.can_create_projects

    def test_system_controller_can_create_projects(self):
        assert UserRole.SYSTEM_CONTROLLER.can_create_projects

    def test_research_coordinator_can_create_projects(self):
        assert UserRole.RESEARCH_COORDINATOR.can_create_projects

    def test_unprivileged_user_cannot_create_projects(self):
        assert not UserRole.NONE.can_create_projects


class TestProjectRole:
    def test_add_as_admin(self):
        assert ProjectRole.PROJECT_ADMIN.can_add_participant
        assert ProjectRole.PROJECT_ADMIN.can_add(ProjectRole.INVESTIGATOR)
        assert ProjectRole.PROJECT_ADMIN.can_add(ProjectRole.RESEARCHER)

    def test_add_as_investigator(self):
        assert ProjectRole.INVESTIGATOR.can_add_participant
        assert ProjectRole.INVESTIGATOR.can_add(ProjectRole.RESEARCHER)
        assert not ProjectRole.INVESTIGATOR.can_add(ProjectRole.INVESTIGATOR)

    def test_add_as_researcher(self):
        assert not ProjectRole.RESEARCHER.can_add_participant
        assert not ProjectRole.RESEARCHER.can_add(ProjectRole.RESEARCHER)

    def test_list_participants(self):
        assert ProjectRole.PROJECT_ADMIN.can_list_participants
        assert not ProjectRole.INVESTIGATOR.can_list_participants
        assert not ProjectRole.RESEARCHER.can_list_participants
