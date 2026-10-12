# Privacy and data-handling disclosure

**STATUS: DRAFT — Stage 4 required deliverable. All sections marked TODO must
be completed and reviewed by the product owner before any public release or
App Store / Play Store submission. Do not publish this file as-is.**

This document describes what data Sarti collects, how it is stored, who can
access it, and how users can export or delete it. It is the basis for the
App Store privacy nutrition label, Play Store data safety form, and any
in-app privacy notice.

---

## 1. What Sarti is

Sarti is a family organizer. It stores calendar events, child profiles, pickup
assignments, and reminders. All family content is end-to-end encrypted: it is
encrypted on the user's device before leaving it and can only be decrypted by
authorized devices in the same family.

---

## 2. Data stored on your device

| Data | Storage | Encrypted |
|---|---|---|
| Family calendar events | SQLCipher local database | Yes — AES-256 via SQLCipher |
| Child profiles and names | SQLCipher local database | Yes |
| Guardian profiles | SQLCipher local database | Yes |
| Pickup assignments | SQLCipher local database | Yes |
| Reminders | SQLCipher local database | Yes |
| Device private keys | Platform secure storage (Keychain / Keystore) | Yes — hardware-backed where available |
| Session token | Platform secure storage | Yes |
| AI cloud consent preference | SQLCipher local database | Yes |
| Child cloud aliases (if cloud AI enabled) | SQLCipher local database | Yes |

---

## 3. Data stored on Sarti servers

Sarti servers store **no plaintext family content**. The server stores only:

| Data | Purpose | Retention |
|---|---|---|
| WebAuthn credential public key | Passkey authentication | Until account deleted |
| Device public keys (encryption + signing) | Key grant authorization | Until device revoked |
| Hashed session token | API authentication | Until session expires or revoked |
| Family and membership metadata (IDs, roles, status) | Authorization | Until family deleted |
| Encrypted sync operations (ciphertext only) | Cross-device sync relay | 7 days |
| Encrypted email suggestions (ciphertext only) | Email-to-calendar proposals | 7 days |
| FCM push token | Opaque sync wake-up | Until device revoked or token rotated |
| Hashed email routing token | Email ingress routing | Until family deleted |

The server cannot read calendar events, child names, event titles, or any
family content. Encrypted ciphertext is relayed and expires; it is not
permanently stored.

---

## 4. Data sent to third-party services

### Push notifications (Google Firebase Cloud Messaging / Apple APNs)
- **What is sent:** An opaque `{"type":"sync_available"}` message only.
- **What is NOT sent:** Event titles, child names, family identifiers, or any
  family content.
- **Provider privacy policy:** TODO — link Firebase/Google privacy policy.

### Optional cloud AI assist (Google Gemini)
- **Requires explicit opt-in.** Defaults off.
- **What is sent:** The raw text sentence entered by the user, with child names
  replaced by random aliases (e.g. `happy-frog-4821`) and locations replaced
  by `place-N` tokens before leaving the device.
- **What is NOT sent:** Family IDs, account identifiers, profile records, keys,
  or the reverse alias mapping.
- **Provider privacy policy:** TODO — link Google AI / Gemini privacy policy.
- **Residual risk:** Pseudonymization is not anonymization. Activity, time,
  recurrence, and sentence structure are still visible to the provider.

### Inbound email (Cloudflare Email Routing)
- **What is sent:** Emails forwarded to your family's Sarti address pass through
  Cloudflare's email routing infrastructure before reaching Sarti servers.
- **What Sarti stores:** Encrypted ciphertext only. The server never stores
  readable email sender, subject, or body.
- **Provider privacy policy:** TODO — link Cloudflare privacy policy.

### Hosting (Google Cloud Run + Neon — beta only)
- **What is processed:** API requests containing authentication metadata and
  encrypted ciphertext. No plaintext family content.
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
- User generates a 12-word recovery phrase (BIP-39).
- The phrase is the only way to restore an encrypted backup to a new device.
- Sarti never transmits or stores the recovery phrase.
- **Note:** Backup restore to a replacement device has open defects BUG-001
  and BUG-002. Backup UI is not shipped until those are resolved.

---

## 6. Children's privacy

Sarti stores child profiles (names, colours, assignments) encrypted on
authorized devices. Child data is never sent to any server in plaintext.
When optional cloud AI is enabled, child names are replaced with random
aliases before leaving the device.

TODO — confirm COPPA / GDPR-K applicability and add required disclosures.
The ML Kit GenAI Prompt API terms currently restrict use in apps directed at
or likely accessed by people under 18. Sarti's P0 UI is for adult guardians
only. Any child-facing client requires a new provider and legal review.

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

## Stage 4 completion checklist for this file

- [ ] All TODO items above completed
- [ ] Legal review of children's privacy section (COPPA / GDPR-K)
- [ ] App Store privacy nutrition label completed and matches this document
- [ ] Play Store data safety form completed and matches this document
- [ ] In-app privacy notice links to published version of this document
- [ ] Product owner sign-off obtained
