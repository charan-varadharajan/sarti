"""S5 scoped roles/admin/caregiver/audit/isolation: real PostgreSQL and AEAD."""

import asyncio
import base64
import hashlib
import json
import os
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from nacl.bindings import (
    crypto_aead_xchacha20poly1305_ietf_decrypt,
    crypto_aead_xchacha20poly1305_ietf_encrypt,
)
from sqlalchemy import func, select, update
from test_stage2_api import Api, StubWebAuthn, b64

from sarti_backend.core.config import Settings
from sarti_backend.db.database import Database
from sarti_backend.db.schema import (
    context_audit,
    families,
    memberships,
    permissions,
    resources,
    sensitive_authorizations,
)
from sarti_backend.households.maintenance import maintain
from sarti_backend.main import create_app

pytestmark = pytest.mark.integration


async def scenario() -> None:
    db = Database(os.environ["SARTI_DATABASE_URL"])
    app = create_app(
        Settings(database_url=os.environ["SARTI_DATABASE_URL"]),
        database=db,
        webauthn=StubWebAuthn(),
    )
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        api = Api(client)
        credential = str(uuid4())
        owner = await api.register(credential)
        peer_credential = str(uuid4())
        peer = await api.register(peer_credential)
        outsider_credential = str(uuid4())
        outsider = await api.register(outsider_credential)
        h = api.headers(owner)
        a = (await client.post("/v1/contexts", headers=h, json={"kind": "household"})).json()
        b = (await client.post("/v1/contexts", headers=h, json={"kind": "household"})).json()
        school = (await client.post("/v1/contexts", headers=h, json={"kind": "school"})).json()
        assert school["role"] == "school_administrator"
        assert (
            await client.post("/v1/contexts", headers=h, json={"kind": "unknown"})
        ).status_code == 422
        assert (
            await client.post(
                "/v1/contexts", headers=h, json={"kind": "household", "name": "private canary"}
            )
        ).status_code == 422
        assert len((await client.get("/v1/contexts", headers=h)).json()) == 3
        assert len((await client.get("/v1/families", headers=h)).json()) == 2
        calendar = next(r for r in a["resources"] if r["kind"] == "calendar")
        invite = (await client.post(f"/v1/families/{a['id']}/invitations", headers=h)).json()
        assert (
            await client.post(
                "/v1/invitations/accept", headers=api.headers(peer), json={"token": invite["token"]}
            )
        ).status_code == 200
        approved = await client.post(
            f"/v1/families/{a['id']}/invitations/{invite['id']}/approve",
            headers=h,
            json={"permissions": [{"resource_id": calendar["id"], "permission": "read"}]},
        )
        assert approved.status_code == 200, approved.text
        assert (
            await client.get(f"/v1/contexts/{a['id']}/members", headers=api.headers(peer))
        ).status_code == 403
        assert (
            await client.get(f"/v1/contexts/{a['id']}/audit", headers=api.headers(outsider))
        ).status_code == 404
        key = os.urandom(32)

        async def change(
            role: str,
            grants: list,
            rev: int,
            action: str = "admin.change",
            target: dict = peer,
            acting: dict = owner,
            cred: str = credential,
            revoked: bool = False,
            context: dict | None = None,
        ) -> dict:
            scope = a if context is None else context
            audit_resource = next(r for r in scope["resources"] if r["kind"] == "admin_audit")
            challenge = (
                await client.post(
                    "/v1/auth/step-up/options",
                    headers=api.headers(acting),
                    json={
                        "action": action,
                        "family_id": scope["id"],
                        "target_id": target["adult_id"],
                        "acl_revision": rev,
                    },
                )
            ).json()
            proof = (
                await client.post(
                    "/v1/auth/step-up/complete",
                    headers=api.headers(acting),
                    json={
                        "challenge_id": challenge["challenge_id"],
                        "credential": {
                            "id": b64(cred.encode()),
                            "challenge": challenge["public_key"]["challenge"],
                        },
                    },
                )
            ).json()["proof"]
            with db.connect() as c:
                epoch = c.execute(
                    select(resources.c.key_epoch).where(
                        resources.c.id == UUID(audit_resource["id"])
                    )
                ).scalar_one()
            op = str(uuid4())
            vector = {acting["device_id"]: 1}
            nonce = os.urandom(24)
            metadata = {
                "protocol": 2,
                "familyId": scope["id"],
                "resourceId": audit_resource["id"],
                "keyEpoch": epoch,
                "operationId": op,
                "authorDeviceId": acting["device_id"],
                "deviceSequence": 1,
                "logicalVersion": vector,
            }
            plaintext = json.dumps(
                {
                    "action": action,
                    "target_id": target["adult_id"],
                    "expected_revision": rev,
                    "detail": "encrypted audit canary",
                }
            ).encode()
            ciphertext = crypto_aead_xchacha20poly1305_ietf_encrypt(
                plaintext, json.dumps(metadata, separators=(",", ":")).encode(), nonce, key
            )
            envelope = {
                "protocol_version": 2,
                "operation_id": op,
                "family_id": scope["id"],
                "resource_id": audit_resource["id"],
                "key_epoch": epoch,
                "device_sequence": 1,
                "logical_version": vector,
                "nonce": b64(nonce),
                "ciphertext": b64(ciphertext),
                "content_digest": b64(hashlib.sha256(nonce + ciphertext).digest()),
            }
            return {
                "role": role,
                "revoked": revoked,
                "permissions": grants,
                "expected_revision": rev,
                "proof": proof,
                "audit": envelope,
                "expected_device_id": target["device_id"],
                "expected_key_digest": hashlib.sha256(b"s" * 32 + b"e" * 32).hexdigest(),
            }

        all_grants = [{"resource_id": r["id"], "permission": "admin"} for r in a["resources"]]
        promote = await change("administrator", all_grants, 1)
        assert (
            await client.put(
                f"/v1/contexts/{b['id']}/members/{peer['adult_id']}", headers=h, json=promote
            )
        ).status_code == 404
        denied = await client.put(
            f"/v1/contexts/{a['id']}/members/{peer['adult_id']}",
            headers=h,
            json={**promote, "role": "school_administrator"},
        )
        assert denied.status_code == 403
        denied = await client.put(
            f"/v1/contexts/{a['id']}/members/{peer['adult_id']}",
            headers=h,
            json={**promote, "expected_device_id": str(uuid4())},
        )
        assert denied.status_code == 409
        assert (
            await client.put(
                f"/v1/contexts/{a['id']}/members/{peer['adult_id']}",
                headers=h,
                json={k: v for k, v in promote.items() if k != "audit"},
            )
        ).status_code == 422
        first = await client.put(
            f"/v1/contexts/{a['id']}/members/{peer['adult_id']}", headers=h, json=promote
        )
        assert first.status_code == 200, first.text
        assert first.json()["acl_revision"] == 2
        directory = (await client.get(f"/v1/contexts/{a['id']}/members", headers=h)).json()
        recipient = next(m for m in directory if m["adult_id"] == peer["adult_id"])
        assert recipient["device"]["device_id"] == peer["device_id"]
        assert (
            recipient["device"]["key_digest"] == hashlib.sha256(b"s" * 32 + b"e" * 32).hexdigest()
        )
        assert {g["resource_id"] for g in recipient["permissions"]} == {
            r["id"] for r in a["resources"]
        }
        assert (
            await client.get(f"/v1/contexts/{school['id']}", headers=api.headers(peer))
        ).status_code == 404

        retry = await client.put(
            f"/v1/contexts/{a['id']}/members/{peer['adult_id']}", headers=h, json=promote
        )
        assert retry.status_code == 200 and retry.json() == first.json()
        # New child stays scoped to its authorized creator. An administrator
        # without that grant must not obtain the whole-household snapshot.
        child = await client.post(
            f"/v1/families/{a['id']}/resources", headers=h, json={"kind": "child_profile"}
        )
        assert child.status_code == 201
        backup_path = f"/v1/families/{a['id']}/backup"
        blob = b"SART\x02" + os.urandom(150)
        assert (
            await client.put(backup_path, headers={**h, "X-Backup-Revision": "0"}, content=blob)
        ).status_code == 204
        assert (await client.get(backup_path, headers=h)).content == blob
        assert (await client.get(backup_path, headers=api.headers(peer))).status_code == 403
        assert (
            await client.put(
                backup_path, headers={**api.headers(peer), "X-Backup-Revision": "1"}, content=blob
            )
        ).status_code == 403
        assert (await client.delete(backup_path, headers=api.headers(peer))).status_code == 403
        assert (await client.get(backup_path, headers=h)).content == blob
        records = (await client.get(f"/v1/contexts/{a['id']}/audit", headers=h)).json()
        assert len(records) == 1
        assert "encrypted audit canary" not in json.dumps(records)
        row = records[0]
        e = row["envelope"]
        m = {
            "protocol": 2,
            "familyId": e["family_id"],
            "resourceId": e["resource_id"],
            "keyEpoch": e["key_epoch"],
            "operationId": e["operation_id"],
            "authorDeviceId": row["actor_device_id"],
            "deviceSequence": e["device_sequence"],
            "logicalVersion": e["logical_version"],
        }

        def raw(x: str) -> bytes:
            return base64.urlsafe_b64decode(x + "=" * (-len(x) % 4))

        decrypted = crypto_aead_xchacha20poly1305_ietf_decrypt(
            raw(e["ciphertext"]),
            json.dumps(m, separators=(",", ":")).encode(),
            raw(e["nonce"]),
            key,
        )
        assert json.loads(decrypted)["detail"] == "encrypted audit canary"
        # A removed administrator re-enters as an ordinary pending guardian.
        # A partial administrator cannot use legacy invitation approval to
        # grant someone else a child's resource it cannot administer.
        with db.transaction() as c:
            c.execute(
                memberships.insert().values(
                    family_id=UUID(a["id"]),
                    adult_id=UUID(outsider["adult_id"]),
                    role="administrator",
                    status="revoked",
                    created_at=datetime.now(UTC),
                    revoked_at=datetime.now(UTC),
                )
            )
        reinvite = (
            await client.post(f"/v1/families/{a['id']}/invitations", headers=api.headers(peer))
        ).json()
        assert (
            await client.post(
                "/v1/invitations/accept",
                headers=api.headers(outsider),
                json={"token": reinvite["token"]},
            )
        ).status_code == 200
        pending = (await client.get("/v1/contexts", headers=api.headers(outsider))).json()
        assert next(x for x in pending if x["id"] == a["id"])["role"] == "guardian"
        approval = f"/v1/families/{a['id']}/invitations/{reinvite['id']}/approve"
        assert (
            await client.post(
                approval,
                headers=api.headers(peer),
                json={"permissions": [{"resource_id": child.json()["id"], "permission": "read"}]},
            )
        ).status_code == 403
        assert (
            await client.post(
                approval,
                headers=h,
                json={"permissions": [{"resource_id": calendar["id"], "permission": "read"}]},
            )
        ).status_code == 200
        assert (
            await client.get(f"/v1/contexts/{a['id']}/members", headers=api.headers(outsider))
        ).status_code == 403
        # Demote original admin, leaving peer administrator; unrelated B untouched.
        demote = await change(
            "guardian",
            [{"resource_id": calendar["id"], "permission": "read"}],
            4,
            target=owner,
            acting=peer,
            cred=peer_credential,
        )
        r = await client.put(
            f"/v1/contexts/{a['id']}/members/{owner['adult_id']}",
            headers=api.headers(peer),
            json=demote,
        )
        assert r.status_code == 200, r.text
        assert (await client.get(f"/v1/contexts/{a['id']}/audit", headers=h)).status_code == 403
        assert (await client.get(f"/v1/contexts/{b['id']}/members", headers=h)).status_code == 200
        last = await change("guardian", [], 5, target=peer, acting=peer, cred=peer_credential)
        assert (
            await client.put(
                f"/v1/contexts/{a['id']}/members/{peer['adult_id']}",
                headers=api.headers(peer),
                json=last,
            )
        ).status_code == 409
        # Caregivers cannot receive household calendar/audit or write privileges.
        caregiver = await change(
            "limited_caregiver",
            [{"resource_id": calendar["id"], "permission": "read"}],
            5,
            target=owner,
            acting=peer,
            cred=peer_credential,
        )
        assert (
            await client.put(
                f"/v1/contexts/{a['id']}/members/{owner['adult_id']}",
                headers=api.headers(peer),
                json=caregiver,
            )
        ).status_code == 403
        caregiver = await change(
            "limited_caregiver", [], 5, target=owner, acting=peer, cred=peer_credential
        )
        caregiver["expires_at"] = (datetime.now(UTC) + timedelta(hours=1)).isoformat()
        r = await client.put(
            f"/v1/contexts/{a['id']}/members/{owner['adult_id']}",
            headers=api.headers(peer),
            json=caregiver,
        )
        assert r.status_code == 200, r.text
        limited = await client.get(f"/v1/contexts/{a['id']}", headers=h)
        assert limited.status_code == 200 and limited.json()["resources"] == []
        assert (
            await client.get(
                f"/v1/families/{a['id']}/resources/{calendar['id']}/devices", headers=h
            )
        ).status_code == 403
        # Server expiry is committed before a denied caller operation, and isolated.
        with db.transaction() as c:
            c.execute(
                update(memberships)
                .where(
                    memberships.c.family_id == UUID(a["id"]),
                    memberships.c.adult_id == UUID(owner["adult_id"]),
                )
                .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
            )
        assert (
            await client.get(f"/v1/families/{a['id']}/calendar-retention", headers=h)
        ).status_code == 404
        assert (await client.get(f"/v1/contexts/{b['id']}/members", headers=h)).status_code == 200
        with db.connect() as c:
            assert (
                c.execute(
                    select(memberships.c.status).where(
                        memberships.c.family_id == UUID(a["id"]),
                        memberships.c.adult_id == UUID(owner["adult_id"]),
                    )
                ).scalar_one()
                == "revoked"
            )
            assert (
                c.execute(
                    select(families.c.acl_revision).where(families.c.id == UUID(b["id"]))
                ).scalar_one()
                == 0
            )
            assert (
                c.execute(
                    select(func.count())
                    .select_from(context_audit)
                    .where(context_audit.c.family_id == UUID(a["id"]))
                ).scalar_one()
                == 3
            )
        # Scheduled maintenance purges expired ciphertext and confirmation state
        # even when no household request arrives; future records remain.
        with db.transaction() as c:
            audit_id = c.execute(
                select(context_audit.c.id)
                .where(context_audit.c.family_id == UUID(a["id"]))
                .limit(1)
            ).scalar_one()
            confirmation_id = c.execute(
                select(sensitive_authorizations.c.id)
                .where(sensitive_authorizations.c.family_id == UUID(a["id"]))
                .limit(1)
            ).scalar_one()
            c.execute(
                update(context_audit)
                .where(context_audit.c.id == audit_id)
                .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
            )
            c.execute(
                update(sensitive_authorizations)
                .where(sensitive_authorizations.c.id == confirmation_id)
                .values(expires_at=datetime.now(UTC) - timedelta(seconds=1))
            )
        with db.transaction() as c:
            counts = maintain(c)
            assert counts["expired_audit_records"] >= 1 and counts["expired_confirmations"] >= 1
            assert (
                c.execute(select(context_audit.c.id).where(context_audit.c.id == audit_id)).first()
                is None
            )
            assert (
                c.execute(
                    select(sensitive_authorizations.c.id).where(
                        sensitive_authorizations.c.id == confirmation_id
                    )
                ).first()
                is None
            )
            assert (
                c.execute(
                    select(func.count())
                    .select_from(context_audit)
                    .where(context_audit.c.family_id == UUID(a["id"]))
                ).scalar_one()
                == 2
            )
        # Prepared second administrator: simultaneous self-demotions can never
        # both remove the final permanent administrator.
        with db.transaction() as c:
            c.execute(
                memberships.insert().values(
                    family_id=UUID(b["id"]),
                    adult_id=UUID(outsider["adult_id"]),
                    role="administrator",
                    status="active",
                    created_at=datetime.now(UTC),
                )
            )
            c.execute(
                permissions.insert(),
                [
                    {
                        "resource_id": UUID(r["id"]),
                        "adult_id": UUID(outsider["adult_id"]),
                        "permission": "admin",
                    }
                    for r in b["resources"]
                ],
            )
        owner_demote = await change("guardian", [], 0, target=owner, context=b)
        outsider_demote = await change(
            "guardian", [], 0, target=outsider, acting=outsider, cred=outsider_credential, context=b
        )
        responses = await asyncio.gather(
            client.put(
                f"/v1/contexts/{b['id']}/members/{owner['adult_id']}", headers=h, json=owner_demote
            ),
            client.put(
                f"/v1/contexts/{b['id']}/members/{outsider['adult_id']}",
                headers=api.headers(outsider),
                json=outsider_demote,
            ),
        )
        assert sorted(r.status_code for r in responses) == [200, 409]
        with db.connect() as c:
            assert (
                c.execute(
                    select(func.count())
                    .select_from(memberships)
                    .where(
                        memberships.c.family_id == UUID(b["id"]),
                        memberships.c.role == "administrator",
                        memberships.c.status == "active",
                    )
                ).scalar_one()
                == 1
            )
    with db.transaction() as c:
        c.execute(
            families.delete().where(families.c.id.in_([UUID(x["id"]) for x in (a, b, school)]))
        )
    db.close()


def test_scoped_admin_caregiver_audit_expiry_and_cross_context_isolation() -> None:
    asyncio.run(scenario())
