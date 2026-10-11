# System and component context

## People and systems

Adults use one authorized active phone each. The mobile app owns private family
content and calls the Sarti API with operational metadata and ciphertext. The API
uses PostgreSQL. External email, push, and user-owned backup systems cross trust
boundaries and remain unselected before Stage 3.

## Mobile component boundaries

`app` composes Riverpod providers and UI. `core` owns errors and cross-cutting
types. Feature modules own domain/application behavior. Adapters own SQLCipher,
HTTP, platform authentication, notifications, native AI, and backups. UI depends
on application interfaces; adapters depend inward on those interfaces.

## Backend component boundaries

`api` owns HTTP routing and schemas. `core` owns configuration, safe errors,
logging, and tenant context. `db` owns connections and migrations. Future domain
modules will own services and repositories. No route may issue arbitrary SQL or
accept a caller-provided family identifier without tenant authorization.

## Stage 2 runtime

Flutter owns the SQLCipher calendar, secure device/resource keys, recurrence,
reminders, encrypted outbox, and conflicts. FastAPI owns WebAuthn verification,
active-device state, family/resource authorization, sealed grants, and the opaque
relay. It does not process plaintext family content or implement AI, email,
backup/recovery, remote push, export, or deletion workflows.
