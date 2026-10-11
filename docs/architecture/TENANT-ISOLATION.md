# Tenant isolation

The family is the tenant boundary. A protected request passes four separate
checks: valid session, active device, active family membership, then role or
resource permission. UUID possession never grants access. Family owners manage
children, invitations, approvals, and guardian removal. Guardians receive only
the resources and read/write/admin levels explicitly approved by the owner.

Server queries include family and resource scope. Invitation acceptance creates
a pending membership; it conveys no content access until owner approval.
Invitation tokens are random, stored only as hashes, expire after 48 hours, are
one-use, and each family is limited to five open/pending invitations. Removing a
guardian revokes permissions and advances every family resource key epoch.

The PostgreSQL integration suite creates two unrelated adults/families and proves
that outsider relay reads are denied even when the requested family has no
operations. PostgreSQL row-level security remains unresolved; application
authorization is the implemented control and cannot be bypassed by repositories.
