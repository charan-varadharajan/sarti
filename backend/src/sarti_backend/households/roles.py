"""Scoped role policy. Role labels never replace independent resource grants."""

from enum import StrEnum


class ContextKind(StrEnum):
    HOUSEHOLD = "household"
    CLASSROOM = "classroom"
    ACTIVITY = "activity"
    SCHOOL = "school"


class Role(StrEnum):
    ADMINISTRATOR = "administrator"
    GUARDIAN = "guardian"
    CAREGIVER = "limited_caregiver"
    TEACHER = "teacher"
    VOLUNTEER = "parent_volunteer"
    CLASSROOM_ADMIN = "classroom_administrator"
    SCHOOL_ADMIN = "school_administrator"
    SUBSCRIBER = "school_calendar_subscriber"


ROLES = {
    ContextKind.HOUSEHOLD: {Role.ADMINISTRATOR, Role.GUARDIAN, Role.CAREGIVER},
    ContextKind.CLASSROOM: {Role.CLASSROOM_ADMIN, Role.TEACHER, Role.VOLUNTEER},
    ContextKind.ACTIVITY: {Role.ADMINISTRATOR, Role.TEACHER, Role.VOLUNTEER},
    ContextKind.SCHOOL: {Role.SCHOOL_ADMIN, Role.TEACHER, Role.VOLUNTEER, Role.SUBSCRIBER},
}
ADMIN_ROLES = {Role.ADMINISTRATOR, Role.CLASSROOM_ADMIN, Role.SCHOOL_ADMIN}


def role_allowed(kind: str, role: str) -> bool:
    try:
        return Role(role) in ROLES[ContextKind(kind)]
    except ValueError:
        return False


def permits(kind: str, role: str, action: str, grant: str | None = None) -> bool:
    if not role_allowed(kind, role):
        return False
    if action in {"membership.manage", "context.close", "roles.assign"}:
        return Role(role) in ADMIN_ROLES
    if action == "content.read":
        return grant in {"read", "write", "admin"}
    if action == "content.write":
        return role not in {Role.CAREGIVER, Role.SUBSCRIBER, Role.VOLUNTEER} and grant in {
            "write",
            "admin",
        }
    if action == "keys.grant":
        return role not in {Role.CAREGIVER, Role.SUBSCRIBER, Role.VOLUNTEER} and grant == "admin"
    return False
