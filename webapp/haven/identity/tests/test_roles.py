from itertools import permutations

from identity.roles import ProjectRole


class TestProjectRole:
    ALLOWED_CREATIONS = {
        (ProjectRole.INVESTIGATOR, ProjectRole.RESEARCHER),
    }

    # Everything else should be disallowed
    DISALLOWED_CREATIONS = set(permutations(ProjectRole.ALL, 2)) - ALLOWED_CREATIONS
