# Test plan: guacamole-user-sync v0.7.0 → v0.8.0 upgrade

Issue: 258 — Guacamole connections disappear

## 1. Feature under test

`SRERemoteDesktopComponent`
(`data_safe_haven/infrastructure/programs/sre/remote_desktop.py`) deploys an
Azure Container Instance group that includes a `guacamole-user-sync`
container. This container periodically syncs LDAP users/groups into the
Guacamole PostgreSQL database. The underlying bug (connection permissions
getting wiped by an `ON DELETE CASCADE` when LDAP returns 0 users/groups) is
fixed upstream in `guacamole-user-sync` v0.8.0
(alan-turing-institute/guacamole-user-sync#32), which restores
`guacamole_connection_permission` rows on each sync run — but only if it is
told which groups should hold which permissions.

The change under test:

1. Bump the container image tag from
   `ghcr.io/alan-turing-institute/guacamole-user-sync:v0.7.0` to `:v0.8.0`
   (`remote_desktop.py:291`).
2. Add a new `GUACAMOLE_GROUP_PERMISSIONS` environment variable to that
   container, per the v0.8.0 README:
   - Format: semicolon-separated `group_name=PERM1,PERM2,...` entries, e.g.
     `admins=READ,UPDATE,DELETE,ADMINISTER;users=READ`.
   - Valid permissions: `READ`, `UPDATE`, `DELETE`, `ADMINISTER`.
   - Each `group_name` **must exactly match** a group name already selected
     by `LDAP_GROUP_BASE_DN`/`LDAP_GROUP_FILTER` — i.e. it must be the real
     LDAP group CN, not a label.
   - If unset, the sync leaves `guacamole_connection_permission` untouched
     (this is why the container currently loses permissions silently).
3. Wire the two LDAP group names into `SRERemoteDesktopComponent`:
   - System administrator group → `READ, UPDATE, DELETE, ADMINISTER`
   - User group → `READ`

   `declarative_sre.py` already computes these names in `ldap_group_names`
   (`admin_group_name`, `user_group_name`, plus `privileged_user_group_name`,
   which is not in scope here) and exports them under the `ldap` stack
   output. `SRERemoteDesktopProps` does not currently receive them — it only
   receives the derived `ldap_group_filter` /`ldap_group_search_base`. The
   implementation will need to add `admin_group_name` and `user_group_name`
   (or equivalent) as new `Input[str]` fields on `SRERemoteDesktopProps` and
   pass them through from `declarative_sre.py`. These are plain strings
   already available on `ldap_group_names` at program-construction time —
   there's no need to round-trip them through a Pulumi stack output/`Output`
   to wire them into `SRERemoteDesktopProps`; they can be passed directly as
   parameters, the same way `ldap_group_filter` is passed today.

## 2. Scope

**In scope** — unit-level Pulumi component tests, consistent with the
existing suite in `tests/infrastructure/programs/sre/` (e.g.
`test_userservices.py`, `test_application_gateway.py`), which run against
`pulumi.runtime.Mocks` rather than real Azure resources:

- Image tag is bumped correctly.
- `GUACAMOLE_GROUP_PERMISSIONS` is present, well-formed, and contains the
  correct permissions for the correct groups.
- The group names used in the env var are the *same* group names exported
  as SRE stack outputs (`ldap_group_names["admin_group_name"]` /
  `["user_group_name"]`) — i.e. no hardcoding/drift between what
  `guacamole-user-sync` is told and what actually gets created in
  Entra/LDAP.
- No regression to existing env vars / container config (LDAP connection
  settings, Postgres settings, other containers in the group).

**Out of scope** (not exercised by these tests, called out as risk instead):

- Real deployment / `pulumi up` against Azure.
- Real LDAP or Postgres behaviour, or the `guacamole-user-sync` binary
  itself (that logic is tested upstream, in the `guacamole-user-sync`
  repo's own `test_postgresql.py` / `test_synchronise.py`).
- End-to-end verification that permissions actually persist after an LDAP
  0-result event — this is what the *feature* fixes, but confirming it
  requires an integration/manual test against a deployed SRE (tracked as a
  follow-up, see §6).

## 3. Test approach

Follow the existing pattern in `tests/infrastructure/programs/sre/`:

- Use the module-level `pulumi.runtime.set_mocks(...)` already set up in
  `conftest.py`, so `ContainerGroup` creation runs without touching Azure.
- Add `remote_desktop_props` and `remote_desktop_component` fixtures to
  `tests/infrastructure/programs/sre/conftest.py` (not test-file-local),
  mirroring how `dns`/`networking`/`monitoring_elements` are already shared
  there — `SRERemoteDesktopComponent` is a plausible dependency for other
  future component tests (e.g. anything asserting on `remote_desktop.exports`),
  so it belongs alongside the other component fixtures rather than living
  only in the new test file.
- Reuse existing `conftest.py` fixtures wherever they already provide what
  `SRERemoteDesktopProps` needs, rather than inventing new ones:
  `dockerhub_credentials`, `location`, `resource_group`, `stack_name`,
  `tags`, `monitoring_elements` (for `log_analytics_workspace`), `dns` (for
  `dns.ip_address`), `networking` (for `subnet_guacamole_containers` /
  `subnet_guacamole_containers_support`), `ldap_group_search_base`,
  `ldap_server_hostname`, `ldap_user_search_base`, `ldap_user_filter`.
  Only `admin_group_name`, `user_group_name`, and an `ldap_group_filter`
  fixture (`ldap_group_search_base` exists already, but nothing currently
  builds the filter string) are genuinely new.
- Since `admin_group_name`/`user_group_name` are plain `str` values (not
  Pulumi `Output`s) both in the real program and in
  `SRERemoteDesktopProps`, fixtures for them are plain `str` fixtures too —
  no `Output.apply`/mocking needed to produce or compare them.
- Assertions that touch the container's `environment_variables` still run
  inside `@pulumi.runtime.test` methods via `Output.apply(...)`, per the
  existing convention, because `container_group.containers` itself is a
  `pulumi.Output[list[ContainerArgs]]` — only the *comparison side*
  (`admin_group_name`, `user_group_name`) is plain and needs no unwrapping.
- Reach into `remote_desktop_component.container_group.containers` exactly
  as `test_shared_db_usernames` does in `test_userservices.py`: find the
  `guacamole-user-sync` entry by `name`, then search its
  `environment_variables` list by `name` for the variable under test.
- Use `tests/infrastructure/programs/resource_assertions.py`'s
  `assert_equal` / `assert_equal_json` helpers for the actual comparisons,
  for consistency with the rest of the suite.

## 4. Fixtures needed (in `tests/infrastructure/programs/sre/conftest.py`)

| Fixture | Notes |
|---|---|
| `admin_group_name` | New. Plain `str`, e.g. `"Data Safe Haven SRE unit test Administrators"`. |
| `user_group_name` | New. Plain `str`, e.g. `"Data Safe Haven SRE unit test Users"`. |
| `ldap_group_filter` | New. Currently only `test_userservices.py` builds `ldap_group_names` inline (inside its local `ldap_user_filter` fixture) to construct a filter string, and only for the *user* filter. Refactor `ldap_user_filter` to reuse the new `admin_group_name`/`user_group_name` fixtures instead of its own inline dict, and add a sibling `ldap_group_filter` fixture built the same way — both then share one definition of the group names, matching how `declarative_sre.py` derives `ldap_group_filter` and `ldap_user_filter` from the same `ldap_group_names`. |
| `remote_desktop_props` | New. `SRERemoteDesktopProps` built entirely from existing fixtures (see §3) plus `admin_group_name`/`user_group_name`/`ldap_group_filter`. No new subnet/network/credential fixtures required. |
| `remote_desktop_component` | New. `SRERemoteDesktopComponent` built from `remote_desktop_props`, `stack_name`, `tags` — mirrors `user_services_component`. |

Note: `SRERemoteDesktopProps` requires `subnet_guacamole_containers` and
`subnet_guacamole_containers_support`; both already exist as fixtures in
`conftest.py` — confirm the exact attribute name for the latter when
writing the fixture (`networking.subnet_guacamole_containers`, per
`declarative_sre.py:368`; the `_support` subnet's exact source should be
checked against `SRENetworkingComponent`'s exports at implementation time).

## 5. Test cases

Scoped to the current feature only (image bump + `GUACAMOLE_GROUP_PERMISSIONS`
correctness) — general component-creation sanity checks, env-var-format
validation, and unrelated-container/unrelated-env-var regression checks are
left to the broader test suite rather than duplicated here.

1. **`test_guacamole_user_sync_image_version`**
   Locate the `guacamole-user-sync` container in
   `container_group.containers` and assert `image ==
   "ghcr.io/alan-turing-institute/guacamole-user-sync:v0.8.0"`.

2. **`test_guacamole_group_permissions_env_var_present`**
   Assert an environment variable named `GUACAMOLE_GROUP_PERMISSIONS`
   exists on the `guacamole-user-sync` container (not secure/omitted).

3. **`test_guacamole_group_permissions_admin_group`**
   Parse the `GUACAMOLE_GROUP_PERMISSIONS` value (split on `;`, then `=`,
   then `,`) and assert the entry for `admin_group_name` grants exactly
   `{READ, UPDATE, DELETE, ADMINISTER}` (order-independent set comparison,
   since the upstream format doesn't guarantee ordering within/between
   entries).

4. **`test_guacamole_group_permissions_user_group`**
   Same, but assert the entry for `user_group_name` grants exactly
   `{READ}` — and, importantly, does **not** include `UPDATE`, `DELETE`, or
   `ADMINISTER` (this is the crux of the least-privilege requirement in the
   issue).

5. **`test_guacamole_group_permissions_no_extra_groups`**
   Assert the parsed permissions map contains exactly the two expected
   group names and no others (guards against accidentally including
   `privileged_user_group_name` or a stray/default group).

6. **`test_guacamole_group_names_match_fixtures`**
   Assert the group names embedded in `GUACAMOLE_GROUP_PERMISSIONS` are
   literally equal to the `admin_group_name` / `user_group_name` fixture
   values passed into `remote_desktop_props` — a plain string comparison
   (no `Output.apply` needed on the fixture side, since these are passed as
   plain parameters, per §3). Guards against the implementation
   accidentally hardcoding a group name, or passing the wrong prop into the
   wrong slot (e.g. swapping admin/user).

## 6. Risks / open questions to flag in the PR (not resolvable by unit tests alone)

- **Group-name matching is exact-string, case-sensitive** per the
  `guacamole-user-sync` README ("Each group name must match the name of a
  group already selected by `LDAP_GROUP_BASE_DN`/`LDAP_GROUP_FILTER`").
  Unit tests only confirm that `SRERemoteDesktopComponent` correctly
  forwards whatever `admin_group_name`/`user_group_name` values it is
  given into `GUACAMOLE_GROUP_PERMISSIONS` — they don't (and can't) confirm
  that `declarative_sre.py` passes in the *same* strings it uses elsewhere
  (`ldap_group_names`, exported under the `ldap` stack output) or that
  those match the real LDAP group CNs created in Entra ID. That wiring is a
  one-line, easily-reviewed diff in `declarative_sre.py`, so it's called
  out here as a review point rather than a unit test.
- **No automated coverage of the actual bug fix** (permissions surviving an
  LDAP 0-result blip) — that's inherently an integration concern. Recommend
  a manual post-deploy check on a test SRE: trigger/simulate an LDAP outage
  (or wait for `REPEAT_INTERVAL`), then confirm
  `guacamole_connection_permission` rows are restored rather than left
  empty.
- Confirm whether `privileged_user_group_name` should also get a
  permission entry — out of scope per the issue as written (only admin and
  user groups are mentioned), but worth a explicit call-out/question in the
  PR description in case it's an oversight in the requirements.
