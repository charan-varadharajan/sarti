# Module catalog

## Implemented mobile foundation

| Module | Responsibility/interface | State and errors | Tests |
| --- | --- | --- | --- |
| `app` | Compose `SartiApp` | Stateless Material bootstrap | Widget smoke test |
| `foundation` | Riverpod providers and readiness UI | `AsyncValue`; generic fail-closed message | Provider-overridden widget test |
| `core/database` | Verify loaded engine via `PRAGMA cipher_version` | Throws when SQLCipher is absent/invalid | Real native-engine test |

The verification module does not persist data or manage production keys.

## Implemented backend foundation

| Module | Responsibility/interface | State and errors | Tests |
| --- | --- | --- | --- |
| `api.health` | Liveness and PostgreSQL readiness | Typed response; 503 without details | Unit, contract, Docker smoke |
| `core.config` | Typed `SARTI_` environment settings | Fails startup on missing DB URL | Static/type checks |
| `core.errors` | Stable safe API errors | Generic external messages | Error security test |
| `core.logging` | Allowlisted JSON operational logs | Excludes arbitrary context | Log canary test |
| `core.tenant` | Fail-closed family-scope assertion | 404-style denial | Two-family unit tests |
| `db.database` | SQLAlchemy engine and readiness | Sanitized unavailable event | PostgreSQL integration |

## Planned P0 modules

Identity/device registry, family roles, calendar, suggestions/on-device AI,
encrypted local persistence, E2EE/key lifecycle, sync/conflicts, notifications,
jobs, email intake, backup/recovery, and export/deletion remain unimplemented.
Each requires its own interfaces, security assumptions, and test mapping before
implementation.
