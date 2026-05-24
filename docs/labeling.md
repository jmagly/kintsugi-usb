# Physical Labeling Scheme

Every Kintsugi USB that leaves the maintainer's hands gets a physical label. The label lets a recipient identify what they're holding and who to ask for help, and lets the maintainer trace each copy back to a tracked asset record. This matters because a rescue drive may sit in a drawer for a year before it's needed — by then, an unlabeled stick is indistinguishable from any other USB, and the person holding it may not be the person who received it.

This scheme covers the **master** and every **distributed copy**. It is intentionally low-tech: a printed label and a serial. No app, no QR-code dependency, no network lookup required to read it.

## What goes on the label

Four fields, always, in this order:

| Field | Example | Why |
|-------|---------|-----|
| **Name** | `Kintsugi USB — Rescue + AI` | So a non-technical holder knows what it is. |
| **Version** | `v2026.5.0` | CalVer release line the image was built from (`YYYY.M.PATCH`). Tells the maintainer which build to support or re-image. |
| **Serial** | `KIN-202605-007` | Unique per physical copy. The key that links to the asset record (see below). |
| **Contact** | `roctinam · git.integrolabs.net/roctinam/kintsugi-usb` | Where the recipient gets help or reports a problem. |

A fifth line is recommended where the label has room:

- **Verify reminder** — `Verify before flashing — see README` — a one-line nudge toward `scripts/verify-image.sh`. A label is not a substitute for checksum verification; it only identifies the drive.

### What must NOT go on the label

- **No secrets.** No tokens, passwords, Wi-Fi keys, or recovery passphrases — ever. A label is visible to anyone who can see the drive. (See [SECURITY.md](../SECURITY.md) and the repo's token-security rules.)
- **No recipient PII beyond what the recipient consents to.** A first name or handle is fine; full names, addresses, or phone numbers are not. The serial — not the recipient's identity — is the tracking key.
- **No fleet internals.** Internal hostnames, IP addresses, or which hosts the drive is meant to recover do **not** belong on a physical label. That mapping lives in the CMDB (private), keyed by serial.

## Serial-number scheme

```
KIN-YYYYMM-NNN
│   │      │
│   │      └─ copy sequence within that batch, zero-padded (001–999)
│   └─ build year + month (ties to the CalVer release line)
└─ fixed prefix (Kintsugi)
```

Examples:

| Serial | Meaning |
|--------|---------|
| `KIN-202605-001` | First copy imaged from the 2026.5 release line. |
| `KIN-202605-007` | Seventh copy, same batch. |
| `KIN-202608-001` | First copy of a later (2026.8) batch. |

Rules:

- **Serials are never reused.** A retired or destroyed drive's serial is closed in the CMDB, not reassigned.
- **The master is `KIN-YYYYMM-000`** by convention — sequence `000` is reserved for the maintainer's master so it sorts first and is never confused with a distributed copy.
- **Re-imaging a drive mints a new serial** if the version changes, and the old serial is marked superseded in the CMDB. (The physical stick is the same; the tracked artifact is not.)

### Linking the serial to the CMDB

The serial is the primary key into the asset record. The authoritative `serial → recipient` and `serial → version → date` mapping lives in the fleet CMDB — `roctinam/itops` `OpsInventory.yaml` — under the Kintsugi USB asset's distribution-copies list. It is **not** stored in this public repo, because it associates serials with recipients.

A CMDB entry for a copy records, at minimum:

| CMDB field | Example |
|------------|---------|
| `serial` | `KIN-202605-007` |
| `version` | `v2026.5.0` |
| `imaged_date` | `2026-05-20` |
| `recipient` | (private — handle or first name) |
| `status` | `active` \| `superseded` \| `retired` \| `destroyed` |

When you label a drive, you create the matching CMDB row in the same step. A labeled drive with no CMDB row, or a CMDB row with no physical label, is drift — fix it before the drive is handed off.

## Printable label template

Plain-text template sized for a standard USB stick or an SSK-style enclosure. Fill the four fields, print, trim to fit, and apply to the flat face of the enclosure. A second identical label on the cap (if removable) survives cap loss.

```
┌─────────────────────────────────────┐
│  KINTSUGI USB — Rescue + AI          │
│  Version:  v2026.5.0                 │
│  Serial:   KIN-202605-007            │
│  Help:     git.integrolabs.net/      │
│            roctinam/kintsugi-usb     │
│  Verify before flashing — see README │
└─────────────────────────────────────┘
```

Compact variant for small enclosures where the box won't fit:

```
KINTSUGI USB  v2026.5.0
KIN-202605-007
help: roctinam/kintsugi-usb
```

Production notes:

- Use a label printer or laser print on adhesive label stock; inkjet smears and fades. A rescue drive must stay readable for years.
- Cover the printed label with a strip of clear tape, or use a laminated label — handling rubs ink off bare paper.
- Keep the font large enough to read without glasses; the holder during an incident may be stressed and in poor light.

## Storage and handling

- **Master**: store separately from distributed copies, in a known, access-controlled location. The master is `KIN-YYYYMM-000` and is the source of truth for re-imaging.
- **Distributed copies**: a rescue drive is only useful if it's findable when a system is down. Recipients should store it somewhere obvious and stable (taped inside a server-rack door, a labeled drawer, a go-bag) — not loose in a junk drawer.
- **Environment**: USB flash and SSDs tolerate normal handling, but avoid sustained heat (a hot car, a radiator) and physical crushing. Flash cells are not infinitely durable; a drive that has sat unused for years should be re-verified (`scripts/check-drive-health.sh` / `scripts/verify-image.sh`) before relied on.
- **Re-labeling**: if a drive is re-imaged to a new version, remove the old label, apply a new one with the new serial, and update the CMDB (old serial → `superseded`, new serial → `active`). Never leave a stale version number on a drive.
- **Retirement / disposal**: before discarding or repurposing a drive, securely wipe it (the persistence partition may carry fleet-context payloads) and mark its serial `destroyed` in the CMDB. A discarded labeled drive is both a data-leak risk and a provenance gap.

## Verification

Before a labeled drive is handed off, confirm all three are consistent:

1. **Label ↔ image** — the version on the label matches the image actually written. Run `scripts/verify-image.sh` against the image that was flashed; confirm the release line matches the label.
2. **Label ↔ CMDB** — the serial on the label exists as an `active` row in `OpsInventory.yaml`, with the same version and the correct recipient.
3. **No secrets / PII on the label** — re-read the physical label and confirm it carries only the four approved fields (plus the verify reminder). If anything else is on it, reprint.

A handoff is not complete until all three checks pass.

## Related

- [README.md](../README.md) — recipient quick start and verification
- [SECURITY.md](../SECURITY.md) — trust boundary; what the maintainer attests to
- [`scripts/verify-image.sh`](../scripts/verify-image.sh) — checksum (and, from v1.1, signature) verification
- `roctinam/itops` `OpsInventory.yaml` — authoritative CMDB asset + distribution-copies record (private)
- Risk register R-08 (recipient hardware variance — support triage by version/serial) and R-11 (non-technical recipient — the label's name + contact fields exist for them)
