from projects.roles import ProjectRole


class TestProjectRoleAddParticipants:
    def test_project_admin_can_add_participants(self):
        assert ProjectRole.PROJECT_ADMIN.can_add_participants

    def test_research_coordinator_can_add_participants(self):
        assert ProjectRole.RESEARCH_COORDINATOR.can_add_participants

    def test_investigator_can_add_participants(self):
        assert ProjectRole.INVESTIGATOR.can_add_participants

    def test_researcher_cannot_add_participants(self):
        assert not ProjectRole.RESEARCHER.can_add_participants


class TestProjectRoleAssignableRoles:
    def test_project_admin_can_assign_any_roles(self):
        assert ProjectRole.PROJECT_ADMIN.can_assign_role(ProjectRole.RESEARCH_COORDINATOR)
        assert ProjectRole.PROJECT_ADMIN.can_assign_role(ProjectRole.INVESTIGATOR)
        assert ProjectRole.PROJECT_ADMIN.can_assign_role(ProjectRole.RESEARCHER)

    def test_research_coordinator_can_assign_any_roles(self):
        assert ProjectRole.RESEARCH_COORDINATOR.can_assign_role(ProjectRole.RESEARCH_COORDINATOR)
        assert ProjectRole.RESEARCH_COORDINATOR.can_assign_role(ProjectRole.INVESTIGATOR)
        assert ProjectRole.RESEARCH_COORDINATOR.can_assign_role(ProjectRole.RESEARCHER)

    def test_investigator_can_only_assign_researchers(self):
        assert ProjectRole.INVESTIGATOR.can_assign_role(ProjectRole.RESEARCHER)
        assert not ProjectRole.INVESTIGATOR.can_assign_role(ProjectRole.INVESTIGATOR)

    def test_researcher_cannot_assign_roles(self):
        assert ProjectRole.RESEARCHER.assignable_roles == []
        assert not ProjectRole.RESEARCHER.can_assign_role(ProjectRole.RESEARCHER)


class TestProjectRoleListParticipants:
    def test_project_admin_can_list_participants(self):
        assert ProjectRole.PROJECT_ADMIN.can_list_participants

    def test_research_coordinator_can_list_participants(self):
        assert ProjectRole.RESEARCH_COORDINATOR.can_list_participants

    def test_investigator_can_list_participants(self):
        assert ProjectRole.INVESTIGATOR.can_list_participants

    def test_researcher_cannot_list_participants(self):
        assert not ProjectRole.RESEARCHER.can_list_participants
