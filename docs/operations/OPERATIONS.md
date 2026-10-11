# Operations

## Current setup

Stage 1 contains documentation only. Python 3.13.1 and Docker 29.6.1 were observed
on the initial workstation. Flutter was not installed. These observations are not
project version commitments.

## Configuration and secrets

Commit an example environment file with names and safe placeholders only when
configuration exists. Runtime secrets must come from an approved secret source,
must never be committed or logged, and must be rotated when exposure is suspected.

## Future runbooks

Before runnable components are accepted, document pinned toolchain versions,
bootstrap, local services, migrations, builds, tests, troubleshooting, backup and
recovery, release, rollback, deletion, retention jobs, and incident response.

Production hosting, monitoring vendors, email delivery, push credentials, and
backup destinations are undecided and require review before configuration.
