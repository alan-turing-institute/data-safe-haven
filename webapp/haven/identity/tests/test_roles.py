from itertools import permutations

from identity.roles import ProjectRole, UserRole


class TestUserRole:
    def test_superuser_can_create_any_roles(self):
        assert UserRole.SYSTEM_CONTROLLER in UserRole.SUPERUSER.creatable_roles
        assert UserRole.RESEARCH_COORDINATOR in UserRole.SUPERUSER.creatable_roles
        assert UserRole.all_roles() == UserRole.SUPERUSER.creatable_roles

    def test_creatable_roles(self):
        assert UserRole.RESEARCH_COORDINATOR in UserRole.SYSTEM_CONTROLLER.creatable_roles
        assert UserRole.SYSTEM_CONTROLLER not in UserRole.SYSTEM_CONTROLLER.creatable_roles

    def test_superuser_can_create_projects(self):
        assert UserRole.SUPERUSER.can_create_projects

    def test_system_controller_can_create_projects(self):
        assert UserRole.SYSTEM_CONTROLLER.can_create_projects

    def test_research_coordinator_can_create_projects(self):
        assert UserRole.RESEARCH_COORDINATOR.can_create_projects

    def test_unprivileged_user_cannot_create_projects(self):
        assert not UserRole.NONE.can_create_projects


class TestProjectRole:
    ALLOWED_CREATIONS = {
        (ProjectRole.INVESTIGATOR, ProjectRole.RESEARCHER),
    }

    # Everything else should be disallowed
    DISALLOWED_CREATIONS = set(permutations(ProjectRole.ALL, 2)) - ALLOWED_CREATIONS
