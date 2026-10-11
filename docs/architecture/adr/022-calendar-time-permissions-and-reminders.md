# ADR-022: Calendar time, permissions, and reminders

- Status: Accepted
- Date: 2026-10-11

Households have one owner and zero or more guardians. Children are profiles and
do not authenticate. Resource permissions are `read`, `write`, and `admin`;
owners administer every family resource, while guardians receive explicit
resource grants. Server authorization metadata never contains family names,
guardian display names, child names, event text, pickup details, or reminder text.

Calendar events store their IANA timezone and local civil start time inside the
encrypted content. Recurrence supports daily, weekly, and monthly frequency,
interval, selected weekdays, count, and local end date. Recurrences remain fixed
to wall-clock time. A nonexistent daylight-saving time moves forward by the gap;
an ambiguous time uses the earlier offset unless an occurrence already records an
explicit offset.

Event deletion is a tombstone. Cancellation preserves an event with cancelled
status. Pickup and dropoff assignments reference encrypted guardian and child
profile IDs. Reminders are scheduled and rendered locally; provider-visible push
payloads are not used for event text.

Onboarding creates a usable family and calendar immediately after passkey and
device setup. Family details and children are optional follow-up actions. The
primary interaction is open the app, see today's schedule, and act through one
prominent add control; week and month are adjacent views rather than separate
setup flows.

