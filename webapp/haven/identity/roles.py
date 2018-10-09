from collections import defaultdict


class Role:
    SYSTEM_CONTROLLER = 'system_controller'
    RESEARCH_COORDINATOR = 'research_coordinator'
    DATA_PROVIDER_REPRESENTATIVE = 'data_provider_representative'
    REFEREE = 'referee'
    INVESTIGATOR = 'investigator'
    RESEARCHER = 'researcher'

GLOBAL_ROLES = (
    (Role.SYSTEM_CONTROLLER, 'System Controller'),
    (Role.RESEARCH_COORDINATOR, 'Research Coordinator'),
)

PROJECT_ROLES = (
    (Role.DATA_PROVIDER_REPRESENTATIVE, 'Data Provider Representative'),
    (Role.RESEARCH_COORDINATOR, 'Research Coordinator'),
    (Role.REFEREE, 'Referee'),
    (Role.INVESTIGATOR, 'Investigator'),
    (Role.RESEARCHER, 'Researcher'),
)


# Define the other roles which can be created by each role
CREATION_PERMISSIONS = defaultdict(list, {
    Role.SYSTEM_CONTROLLER: [
        Role.RESEARCH_COORDINATOR,
        Role.DATA_PROVIDER_REPRESENTATIVE,
        Role.REFEREE,
        Role.INVESTIGATOR,
        Role.RESEARCHER,
    ],
    Role.RESEARCH_COORDINATOR: [
        Role.REFEREE,
        Role.INVESTIGATOR,
        Role.RESEARCHER,
    ],
    Role.INVESTIGATOR: [
        Role.RESEARCHER,
    ],
})
