"""S5-ROLE-001: complete finite role/context/action policy matrix."""

import pytest

from sarti_backend.households.roles import (
    ADMIN_ROLES,
    ROLES,
    ContextKind,
    Role,
    permits,
    role_allowed,
)


@pytest.mark.parametrize("kind", list(ContextKind))
@pytest.mark.parametrize("role", list(Role))
def test_roles_never_escape_assigned_context(kind: ContextKind, role: Role) -> None:
    valid = role in ROLES[kind]
    assert role_allowed(kind, role) == valid
    assert permits(kind, role, "membership.manage") == (valid and role in ADMIN_ROLES)
    assert not permits(kind, role, "content.read")
    assert not permits(kind, role, "content.write")
    assert not permits(kind, role, "keys.grant")
    assert permits(kind, role, "content.read", "read") == valid
    assert permits(kind, role, "content.write", "admin") == (
        valid and role not in {Role.CAREGIVER, Role.SUBSCRIBER, Role.VOLUNTEER}
    )
    assert permits(kind, role, "keys.grant", "admin") == (
        valid and role not in {Role.CAREGIVER, Role.SUBSCRIBER, Role.VOLUNTEER}
    )
    assert not permits(kind, role, "unrecognized.action", "admin")


def test_unknown_roles_contexts_and_grants_deny() -> None:
    assert not role_allowed("household", "superadmin")
    assert not role_allowed("unknown", "administrator")
    assert not permits("household", "administrator", "content.read", "superadmin")
    assert not permits("school", "school_administrator", "household.close", "admin")
