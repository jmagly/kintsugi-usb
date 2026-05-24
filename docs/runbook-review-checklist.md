# Runbook Review Checklist

**Purpose**: operationalize R-15 (AI-assisted runbooks may ship inaccurate guidance) and ADR-003 (Verification Rigor). No runbook ships on a Kintsugi USB without a human review against this checklist and a recorded sign-off.

**Enforced by**: `scripts/check-runbooks.sh` (release gate, wired into `docs/release-process.md`). Tracked as Gitea #33.

## What is a runbook?

Any doc that gives step-by-step operational/recovery procedure containing commands a recipient will run — especially destructive ones (`dd`, `wipefs`, `mkfs`, `cryptsetup`, partition edits). A runbook opts into the gate by carrying this marker near the top:

```html
<!-- runbook -->
```

Reference, non-procedural docs (architecture, requirements, naming) are not runbooks and do not carry the marker.

## Review checklist

A reviewer must confirm **all** of the following before signing off:

- [ ] **Every destructive command requires target re-statement.** Before any command that writes to a block device, the runbook instructs the operator to re-state and confirm the target (e.g. show `lsblk`, confirm `/dev/sdX` is the intended device, never the system disk).
- [ ] **No wrong-direction `dd`/destructive examples.** `if=`/`of=` are correct; no copy-paste hazard that overwrites the wrong device.
- [ ] **Read-before-write where possible.** Prefer `--dry-run`, `testdisk`-style inspection, or a read pass before any irreversible write.
- [ ] **Ends with a verification step** (CLAUDE.md "Verification always"): the final step confirms success (checksum, boot test, `lsblk`/mount check, or smoke test) and catches a wrong-device mistake before it is destructive.
- [ ] **No stale/internal references.** No decommissioned hostnames, dead internal links, or sysops-era paths that won't resolve for a recipient.
- [ ] **Human-reviewed, not unverified AI draft.** A person with domain knowledge has read the whole procedure and vouches for its accuracy.

## Sign-off marker

When the review passes, add this marker near the top of the runbook (just under the title):

```html
<!-- reviewed-by: NAME | YYYY-MM-DD | COMMIT-OR-NA -->
```

- `NAME` — the human reviewer (not a tool).
- `YYYY-MM-DD` — review date.
- `COMMIT-OR-NA` — the commit the review applies to, or `NA` if reviewing pre-commit.

A material change to a runbook **invalidates** the sign-off — re-review and update the marker (new date/commit).

## Gate behavior

`scripts/check-runbooks.sh` scans `docs/` for `<!-- runbook -->` docs and fails the release if any lack a `reviewed-by:` marker. It enforces that the sign-off **exists**; the human review (this checklist) is what gives the sign-off meaning. Bypassing the gate ships an unreviewed runbook into a rescue context — do not.

## References

- @.aiwg/risks/risk-list.md — R-15
- @.aiwg/architecture/adr-003-verification-rigor.md — verification standard
- @docs/release-process.md — where the gate runs
- @scripts/check-runbooks.sh — the enforcer
