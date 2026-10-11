from dataclasses import dataclass
from uuid import UUID

from sarti_backend.core.errors import TenantAccessDenied


@dataclass(frozen=True, slots=True)
class TenantContext:
    family_id: UUID

    def require_family(self, requested_family_id: UUID) -> None:
        if requested_family_id != self.family_id:
            raise TenantAccessDenied
