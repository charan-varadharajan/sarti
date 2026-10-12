# ADR-026: Push notifications

- Status: Accepted
- Date: 2026-10-12

## Decision

Local notifications (already implemented in Stage 2) are extended with
lock-screen sensitivity handling. Remote push uses Firebase Cloud Messaging
for opaque wake-up delivery only.

## Local notifications

`flutter_local_notifications` (already in project) schedules reminders on-device.
Notification content follows OS-native sensitivity rules:

- The app sets `NotificationVisibility.private` on Android and uses
  `DarwinNotificationDetails` with default iOS lock-screen behaviour.
- When the device is locked, the OS shows the generic channel description
  ("Calendar reminders") or hides content per the user's system setting.
- When the device is unlocked, the notification shows the real event title
  and child first name.
- No changes to the OS notification permission model are made. The app uses
  whatever the OS and user settings allow.

## Remote push (opaque wake-up only)

Firebase Cloud Messaging (FCM) delivers a silent data-only push as a hint that
encrypted synchronization may be available. The FCM payload contains only:

```json
{"type": "sync_available"}
```

No event titles, child names, family identifiers, guardian names, or family
content appear in the FCM payload. The provider still processes a device
registration token and delivery metadata; it does not receive calendar content.

The client accepts only that exact one-key payload, coalesces bursts, and asks
the existing encrypted sync engine to catch up. A foreground transition also
requests catch-up because mobile operating systems may delay or coalesce silent
delivery. The client does not decrypt or open SQLCipher from an unauthenticated
background isolate.

## New dependency

`firebase_core 4.15.0` and `firebase_messaging 16.7.0` are pinned in
`pubspec.yaml`. Backend uses pinned `firebase-admin 6.9.0` for server-side FCM
dispatch.

## Client lifecycle

After an authenticated mobile session exists, the client obtains the current
FCM token, registers it through `POST /v1/push/register`, and repeats
registration when Firebase rotates the token. Foreground and notification-open
streams accept only the exact opaque wake-up. The coordinator is implemented
and unit tested, but the shipping bootstrap does not yet create an authenticated
`SartiApiClient`/`SyncEngine`; that integration remains a release blocker.

No remote-notification permission prompt is added for this data-only transport.
Visible reminder permissions remain part of the existing local-reminder flow.

## Backend config

`SARTI_FCM_CREDENTIALS_FILE` — path to Firebase service account JSON.
Absent in development; push is skipped gracefully if not configured.

The mobile deployment additionally needs Firebase project configuration for
each app, APNs credentials uploaded to Firebase, and iOS Push Notifications
signing capability. Configuration and provider credentials are not committed.

## Quiet hours

Quiet hours are enforced by the OS Do Not Disturb setting. The app does not
implement a separate quiet-hours layer in Stage 3.

## Notification grouping

Android: notifications grouped under the `calendar_reminders` channel
(already created in Stage 2). iOS: thread identifier set to family ID hash
(opaque, not the real UUID).
