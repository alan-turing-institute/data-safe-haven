import pytest

from core import recipes
from projects.models import Project
from projects.roles import ProjectRole


@pytest.mark.django_db
class TestCreateProject:
    def test_anonymous_cannot_access_page(self, client, helpers):
        response = client.get('/projects/new')
        helpers.assert_login_redirect(response)

    def test_anonymous_cannot_post_form(self, client, helpers):
        response = client.post('/projects/new')
        helpers.assert_login_redirect(response)

    def test_unprivileged_user_cannot_access_page(self, as_project_participant):
        response = as_project_participant.get('/projects/new')
        assert response.status_code == 403

    def test_unprivileged_user_cannot_post_form(self, as_project_participant):
        response = as_project_participant.post('/projects/new')
        assert response.status_code == 403

    def test_create_project(self, as_research_coordinator):
        response = as_research_coordinator.post(
            '/projects/new',
            {'name': 'my project', 'description': 'a new project'},
        )

        assert response.status_code == 302
        assert response.url == '/projects/'

        project = Project.objects.get()
        assert project.name == 'my project'
        assert project.description == 'a new project'
        assert project.created_by == as_research_coordinator._user


@pytest.mark.django_db
class TestListProjects:
    def test_anonymous_cannot_access_page(self, client, helpers):
        response = client.get('/projects/')
        helpers.assert_login_redirect(response)

    def test_list_owned_projects(self, as_research_coordinator, system_controller):
        my_project = recipes.project.make(created_by=as_research_coordinator._user)
        recipes.project.make(created_by=system_controller)

        response = as_research_coordinator.get('/projects/')

        assert list(response.context['projects']) == [my_project]

    def test_list_involved_projects(self, as_project_participant):
        project1, project2 = recipes.project.make(_quantity=2)

        recipes.participant.make(project=project1, user=as_project_participant._user)

        response = as_project_participant.get('/projects/')

        assert list(response.context['projects']) == [project1]

    def test_list_all_projects(self, research_coordinator, as_system_controller):
        my_project = recipes.project.make(created_by=as_system_controller._user)
        other_project = recipes.project.make(created_by=research_coordinator)

        response = as_system_controller.get('/projects/')

        assert list(response.context['projects']) == [my_project, other_project]


@pytest.mark.django_db
class TestViewProject:
    def test_anonymous_cannot_access_page(self, client, helpers):
        response = client.get('/projects/1')
        helpers.assert_login_redirect(response)

    def test_view_owned_project(self, as_research_coordinator):
        project = recipes.project.make(created_by=as_research_coordinator._user)

        response = as_research_coordinator.get('/projects/%d' % project.id)

        assert response.status_code == 200
        assert response.context['project'] == project

    def test_view_involved_project(self, as_project_participant):
        project1, project2 = recipes.project.make(_quantity=2)
        recipes.participant.make(project=project1, user=as_project_participant._user)

        response = as_project_participant.get('/projects/%d' % project1.id)

        assert response.status_code == 200
        assert response.context['project'] == project1

    def test_cannot_view_other_project(self, as_research_coordinator):
        project = recipes.project.make()

        response = as_research_coordinator.get('/projects/%d' % project.id)

        assert response.status_code == 404

    def test_view_as_system_controller(self, as_system_controller):
        project = recipes.project.make()

        response = as_system_controller.get('/projects/%d' % project.id)

        assert response.status_code == 200
        assert response.context['project'] == project


@pytest.mark.django_db
class TestAddUserToProject:
    def test_anonymous_cannot_access_page(self, client, helpers):
        project = recipes.project.make()
        response = client.get('/projects/%d/participants/add' % project.id)
        helpers.assert_login_redirect(response)

        response = client.post('/projects/%d/participants/add' % project.id)
        helpers.assert_login_redirect(response)

    def test_view_page(self, as_research_coordinator):
        project = recipes.project.make(created_by=as_research_coordinator._user)

        response = as_research_coordinator.get('/projects/%d/participants/add' % project.id)
        assert response.status_code == 200
        assert response.context['project'] == project

    def test_add_new_user_to_project(self, as_research_coordinator):
        project = recipes.project.make(created_by=as_research_coordinator._user)

        response = as_research_coordinator.post('/projects/%d/participants/add' % project.id, {
            'role': ProjectRole.RESEARCHER.value,
            'username': 'newuser',
        })

        assert response.status_code == 302
        assert response.url == '/projects/%d/participants/' % project.id

        assert project.participant_set.count() == 1
        assert project.participant_set.first().user.username == 'newuser'

    def test_returns_404_for_invisible_project(self, as_research_coordinator):
        project = recipes.project.make()

        # Research coordinator shouldn't have visibility of this other project at all
        # so pretend it doesn't exist and raise a 404
        response = as_research_coordinator.get('/projects/%d/participants/add' % project.id)
        assert response.status_code == 404

        response = as_research_coordinator.post('/projects/%d/participants/add' % project.id)
        assert response.status_code == 404

    def test_returns_403_if_no_add_permissions(self, client, researcher):
        # Researchers can't add participants, so do not display the page
        client.force_login(researcher.user)

        response = client.get('/projects/%d/participants/add' % researcher.project.id)
        assert response.status_code == 403

        response = client.post('/projects/%d/participants/add' % researcher.project.id)
        assert response.status_code == 403

    def test_restricts_creation_based_on_role(self, client, investigator):
        # An investigator cannot create another investigator on the project
        client.force_login(investigator.user)
        response = client.post(
            '/projects/%d/participants/add' % investigator.project.id,
            {
                'username': 'newuser',
                'role': ProjectRole.INVESTIGATOR.value,
            })

        assert response.status_code == 200
        assert 'role' in response.context['form'].errors
        assert investigator.project.participant_set.count() == 1

    def test_roles_are_restricted_in_dropdown(self, client, investigator):
        # An investigator should not see 'investigator' as an option
        client.force_login(investigator.user)

        response = client.get('/projects/%d/participants/add' % investigator.project.id)

        assert response.status_code == 200
        role_field = response.context['form']['role'].field
        assert not role_field.valid_value(ProjectRole.INVESTIGATOR.value)


@pytest.mark.django_db
class TestListParticipants:
    def test_anonymous_cannot_access_page(self, client, helpers):
        project = recipes.project.make()
        response = client.get('/projects/%d/participants/' % project.id)
        helpers.assert_login_redirect(response)

    def test_view_page(self, as_research_coordinator):
        project = recipes.project.make(created_by=as_research_coordinator._user)
        researcher = recipes.researcher.make(project=project)
        investigator = recipes.investigator.make(project=project)

        response = as_research_coordinator.get('/projects/%d/participants/' % project.id)

        assert response.status_code == 200
        assert list(response.context['participants']) == [researcher, investigator]

    def test_returns_404_for_invisible_project(self, as_research_coordinator):
        project = recipes.project.make()

        # Research coordinator shouldn't have visibility of this other project at all
        # so pretend it doesn't exist and raise a 404
        response = as_research_coordinator.get('/projects/%d/participants/' % project.id)
        assert response.status_code == 404

    def test_returns_403_for_unauthorised_user(self, client, researcher):
        client.force_login(researcher.user)

        response = client.get('/projects/%d/participants/' % researcher.project.id)
        assert response.status_code == 403
