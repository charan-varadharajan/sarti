from uuid import UUID

import pytest

from sarti_backend.core.errors import TenantAccessDenied
from sarti_backend.core.tenant import TenantContext

FAMILY_A = UUID("00000000-0000-4000-8000-000000000001")
FAMILY_B = UUID("00000000-0000-4000-8000-000000000002")


def test_tenant_context_accepts_its_family() -> None:
    TenantContext(FAMILY_A).require_family(FAMILY_A)


def test_tenant_context_rejects_another_family() -> None:
    with pytest.raises(TenantAccessDenied):
        TenantContext(FAMILY_A).require_family(FAMILY_B)
