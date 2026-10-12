# ADR-031: BIP-39 recovery-phrase conformance

- Status: Accepted
- Date: 2026-10-12
- Supersedes: ADR-025, recovery-phrase generation and validation only
- Related: BUG-001

## Context

ADR-025 requires a 12-word BIP-39 recovery phrase generated from libsodium
randomness. The current implementation instead selects independent words from a
256-word subset and applies no BIP-39 checksum. It cannot be reliably validated
or recovered by standard BIP-39 tooling.

BUG-001 concerns phrase conformance only. It does not change the backup envelope
or resolve BUG-002: a raw SQLCipher database backup still lacks a specified
replacement-device SQLCipher-key recovery path.

## Decision

Adopt the maintained `bip39_mnemonic` package, pinned at `4.1.0`, for BIP-39
English mnemonic encoding and validation. Generate exactly 16 bytes (128 bits)
of entropy through the existing libsodium secure-random API and pass those bytes
to `Mnemonic(entropy, Language.english)`. This produces a 12-word phrase with
the standard checksum; the app must never choose words independently or implement
BIP-39 bit, checksum, or word-list logic itself.

Recovery input is parsed and validated by the same package before key derivation.
Invalid word count, unknown words, or invalid checksum fail before PBKDF2 and
before any database file is written. The phrase remains display-only, shown once
at family creation and not persisted by Sarti.

The existing PBKDF2-HMAC-SHA256 backup-key derivation and encrypted-envelope
format are unchanged by this ADR. This ADR does not make backup restore
production-ready while BUG-002 is unresolved.

## Dependency review

`bip39_mnemonic` 4.1.0 is published by verified publisher `ethicnology.com`,
supports Flutter's iOS and Android targets, is MIT licensed, and accepts
caller-provided entropy for mnemonic construction. Its direct transitive
dependencies are `pointycastle` and `unorm_dart`; Flutter's resolver lock must
record the exact resolved versions. It replaces no existing dependency.

## Verification

The implementation must add automated tests that:

1. reproduce official BIP-39 English test vectors for known entropy and phrases;
2. verify generated phrases contain 12 English BIP-39 words and validate;
3. verify an altered word or checksum fails validation;
4. verify recovery rejects an invalid phrase before creating or replacing a
   local database file; and
5. retain the existing encryption, wrong-phrase, and corruption tests.

The official BIP-39 specification and its linked test vectors are the source of
truth for vector values. The tests must not use production randomness.

## Consequences

New recovery phrases become portable, checksum-validated BIP-39 English
mnemonics. Existing development-only nonconformant phrases are not supported for
new backups; no production recovery phrases exist. This direct mobile dependency
is approved and must remain pinned and covered by the tests in this ADR.
