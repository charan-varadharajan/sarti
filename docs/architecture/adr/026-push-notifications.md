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

Firebase Cloud Messaging (FCM) delivers a silent data-only push to wake the
app for sync. The FCM payload contains only:

```json
{"type": "sync_available"}
```

No event titles, child names, family identifiers, guardian names, or any
family content appear in the FCM payload. APNs/FCM infrastructure never
receives family data.

## New dependency

`firebase_messaging` added to `pubspec.yaml` (pinned). Backend adds
`firebase-admin` to `requirements.txt` for server-side FCM dispatch.

## Backend config

`SARTI_FCM_CREDENTIALS_FILE` — path to Firebase service account JSON.
Absent in development; push is skipped gracefully if not configured.

## Quiet hours

Quiet hours are enforced by the OS Do Not Disturb setting. The app does not
implement a separate quiet-hours layer in Stage 3.

## Notification grouping

Android: notifications grouped under the `calendar_reminders` channel
(already created in Stage 2). iOS: thread identifier set to family ID hash
(opaque, not the real UUID).
