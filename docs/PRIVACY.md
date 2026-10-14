# Privacy and data-handling disclosure

**STATUS: DRAFT — pre-release deliverable. All sections marked TODO must
be completed and reviewed by the product owner before any public release or
App Store / Play Store submission. Do not publish this file as-is.**

This document describes what data Sarti collects, how it is stored, who can
access it, and how users can export or delete it. It is the basis for the
App Store privacy nutrition label, Play Store data safety form, and any
in-app privacy notice.

---

## 1. What Sarti is

Sarti is a family organizer. It stores calendar events, child profiles, pickup
assignments, and reminders. Content sent through Sarti synchronization is
encrypted on an authorized device before leaving it. Automated child/guardian sharing checks pass; physical-device and provider
validation remain release requirements. Optional cloud AI and inbound email
have separate processing boundaries described below. Encryption of sync does
not mean that personal information can never leave your phone.

---

## 2. Data stored on your device

| Data | Storage | Encrypted |
|---|---|---|
| Family calendar events | SQLCipher local database | Yes — AES-256 via SQLCipher |
| Child profiles and names | SQLCipher local database | Yes |
| Guardian profiles | SQLCipher local database | Yes |
| Pickup assignments | SQLCipher local database | Yes |
| Reminders | SQLCipher local database | Yes |
| Device private keys | Platform secure storage (Keychain / Keystore) | Protected by the configured OS secure-storage policy; hardware backing is not yet verified |
| Session token | Platform secure storage | Yes |
| AI cloud consent preference | SQLCipher local database | Yes |
| Retained child aliases (excluded from cloud requests) | SQLCipher local database | Yes |
| Per-request AI labels and reverse mapping | Temporary application memory only; not persisted | Not sent to storage |

---

## 3. Data stored on Sarti servers

Sarti application persistence stores **no plaintext private family content**.
This describes storage, not every processing step: inbound email is temporarily
plaintext before encryption. The server stores:

| Data | Purpose | Retention |
|---|---|---|
| WebAuthn credential public key | Passkey authentication | Until account deleted |
| Device public keys (encryption + signing) | Key grant authorization | Until device revoked |
| Hashed session token | API authentication | Until session expires or revoked |
| Family and membership metadata (IDs, roles, status) | Authorization | Until family deleted |
| Calendar retention period, activation and revision | Admin-managed family configuration, not appointment content | Until family deleted |
| Encrypted sync operations (ciphertext only) | Cross-device sync relay | 7 days |
| Encrypted email suggestions (ciphertext only) | Email-to-calendar proposals | 7 days |
| FCM push token | Opaque sync wake-up | Until device revoked or token rotated |
| Hashed email routing token | Email ingress routing | Until family deleted |
| Encrypted owner backup snapshot | Explicit recovery relay | Until replaced, deleted or family deleted |

The sync/backup services do not hold the keys needed to decrypt calendar or
profile ciphertext. This does not cover plaintext inbound email before sealing
or optional cloud information disclosed outside the encrypted sync flow. Sync
operations and email suggestion ciphertext expire after seven days. Sealed resource-key grants and authorization metadata persist until
their resource, device, family, or account lifecycle removes them.

---

## 4. Data sent to third-party services

### Push notifications (Google Firebase Cloud Messaging / Apple APNs)
- **What is sent:** An opaque `{"type":"sync_available"}` message only.
- **What is NOT sent:** Event titles, child names, family identifiers, or any
  family content.
- **Provider privacy policy:** TODO — link Firebase/Google privacy policy.

### Optional cloud AI assist (Google Gemini)
- **Current availability:** ADR-037 broker implementation is connected to an
  explicit action but disabled on the server by default. Live provider testing
  is deferred by the maintainer; no live-service guarantee. Native/local parsing
  is the primary path and needs no cloud provider.
- **Requires fresh explicit opt-in.** Defaults off; disclosure version 3 does
  not inherit earlier consent. Local parsing remains available when disabled.
- **What may be sent:** A bounded JSON array of supported scheduling tokens,
  with fresh random labels for known children, guardians and places for each
  request. Repeated references within that request share one temporary label.
  Unsupported text blocks submission; raw sentences and arbitrary notes are
  not forwarded. This conservative English grammar limits supported requests.
- **Excluded from the model payload:** Stored aliases, account/family/device IDs,
  profile records, keys, requester identifiers and reverse label mappings.
  Temporary mappings stay in phone memory; no persistent mapping is created.
- **Sarti processing:** The authenticated Sarti server temporarily sees these
  scheduling tokens in memory and sends them to Gemini. This path is outside
  sync/backup E2EE. Provider credentials remain runtime-only on the server; no
  prompts/responses/content hashes are persisted. Adult/day and global/month
  attempt counts expire after 35 days; account deletion purges adult rows.
- **Residual risk:** Scheduling information can still be sensitive or identify
  someone. Token filtering is not a universal PII detector. Network metadata,
  provider credentials and distinctive schedules can allow correlation even
  with fresh labels. This is pseudonymization, not anonymity.
- **Provider handling:** Retention, training, eligibility and production terms
  must be verified before enabling the selected service. Do not promise zero
  retention, no training or anonymous network access. Provider policy: TODO.

### Inbound email (Cloudflare Email Routing)
- **What is sent:** Emails forwarded to your family's Sarti address pass through
  Cloudflare's email routing infrastructure before reaching Sarti servers.
- **What Sarti stores:** Encrypted ciphertext only. The server never stores
  readable email sender, subject, or body.
- **Provider privacy policy:** TODO — link Cloudflare privacy policy.

### Hosting (Google Cloud Run + Neon — beta only)
- **What is processed:** API requests containing authentication metadata and
  encrypted ciphertext for sync/backup. Email ingress additionally processes
  plaintext temporarily before sealing; storage and runtime processing differ.
- **Provider privacy policies:** TODO — link GCP and Neon privacy policies.
- **Note:** Beta hosting only. Production hosting requires a separate approved
  ADR covering regions, subprocessors, and data residency.

---

## 5. Data the user controls

### Export
TODO — implement per ADR-017. User can request a full export of their
decrypted family data. Export format: TODO.

### Deletion
TODO — implement per ADR-017. User can:
- Delete their account (removes all server-side data for that adult)
- Delete their family (removes all server-side family data; other devices
  retain locally cached encrypted data)

Deletion deadlines: TODO — define maximum server-side deletion SLA.

### Backup and recovery
- A parent may explicitly upload one encrypted family snapshot to Sarti. It is
  retained until replaced, deleted by its owner, or the family is deleted.
- The validated BIP-39 phrase stays with the parent. Sarti stores no recovery
  phrase or permanent decryption key. Owner login authorizes downloading opaque
  bytes; local phrase entry is still required to restore.
- Restricted guardians cannot download a full-family snapshot. Physical-device
  recovery and provider backup-retention behavior remain release validation gaps.

---

## 6. Children's privacy

Sarti stores child profiles (names, colours, assignments) encrypted on
authorized devices. Sync and backup content is encrypted before upload.
Optional cloud AI can receive limited scheduling information with temporary
labels if configured and explicitly enabled. This information may still be
sensitive or identifying. Inbound email may contain child information in
plaintext before device-specific encryption. Do not claim that personal
information never leaves the phone. See `product/PRIVACY-MESSAGING.md`.

TODO — confirm COPPA / GDPR-K applicability and add required disclosures.
Sarti's P0 UI is for adult guardians only. Verify the then-current Apple,
Google, Firebase, Gemini, and ML Kit terms with legal counsel before release;
this draft does not establish provider eligibility for child-related data.

---

## 7. Analytics and crash reporting

TODO — ADR-016 (privacy-preserving monitoring) is accepted but not implemented.
No analytics or crash reporting is currently collected. When implemented, only
bounded operational metrics (no family content, no identifiers) will be
collected. This section must be updated before any monitoring is enabled.

---

## 8. Data residency

Beta: Google Cloud Run (region: TODO) and Neon (region: TODO).
Production: TODO — requires approved ADR-018 successor covering region,
subprocessors, and data residency commitments.

---

## 9. Contact

TODO — add privacy contact email / DPO contact before public release.

---

## Pre-release completion checklist for this file

- [ ] All TODO items above completed
- [ ] Legal review of children's privacy section (COPPA / GDPR-K)
- [ ] App Store privacy nutrition label completed and matches this document
- [ ] Play Store data safety form completed and matches this document
- [ ] In-app privacy notice links to published version of this document
- [ ] Product owner sign-off obtained

## Mobile calendar history retention — ADR-039

Family calendar admins choose one week (default), one month, three months, one
year or Never. This applies to calendar entries on family phones, including
private entries evaluated by their own author’s phone; it does not grant admins
private access. Future entries and active recurring series stay. Existing families
preview/adopt before automatic removal. Cleanup runs after authorized sync while
the app is active; pending edits/conflicts and disconnected devices can delay it.
Expired details are removed from local event records and replaced by minimal
causal deletion records. Operational copies needed for unresolved edits/retries
remain until safe to remove. Never stops cleanup, not reverses prior removal.
Existing encrypted backups/exports and offline copies can still contain older
content. The server relay remains seven days; backup lifetime is separate.
Unvalidated family-only restores pause cleanup while BUG-022 remains unresolved.

### Family recovery history (ADR-040)

Encrypted family snapshots may contain historical family resource keys, causal
metadata, unsent appointment/profile intent and deletion/Keep state. They exclude
adult-private resources and use an independent snapshot database key inside the
recovery envelope. The service stores only the existing opaque revisioned blob;
no permanent recovery-decryption key. A user-held phrase decrypts locally.
Restored history can be older than available seven-day sync messages; recovery
does not guarantee latest completeness. Calendar retention does not rewrite
previously exported backups or provider copies.
