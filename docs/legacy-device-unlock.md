# Unlocking Legacy Encrypted USB Drives (IronKey)

Kintsugi can unlock legacy **Imation / IronKey** secure USB drives in the field —
offline, with nothing to download. This guide walks through it end to end.

> **Why this needs anything special:** the IronKey Linux unlocker is a 2015-era
> **32-bit** program. A clean 64-bit Ubuntu ships no 32-bit runtime, so the
> unlocker can't even start. Kintsugi bakes the 32-bit runtime (`i386` +
> `libc6:i386`) into the image at build time, so it works on the rescue drive out
> of the box — see [issue #45](https://git.integrolabs.net/roctinam/kintsugi-usb/issues/45)
> and `scripts/usb-toolkit/legacy-tools-provision.sh`.

## ⚠️ Read this first — the retry counter

Legacy IronKeys **permanently destroy their own data** (crypto-erase) after a set
number of *consecutive wrong passwords* — often 10, but enterprise-provisioned
units can be set lower. There is no recovery after that point.

- **Listing the device is free.** `--show` never touches the password.
- **A wrong password counts.** A correct password resets the counter to zero.
- Only attempt the password when you are confident of it.

## Step 1 — Plug in the key and find the launcher

When you insert a locked IronKey, only its small read-only **launcher partition**
appears (the encrypted volume stays hidden until unlocked). It auto-mounts under
`/media/<you>/IRONKEY` (label may vary).

```bash
ls /media/$USER/IRONKEY/linux/
```

You should see `ironkey.exe` in the `linux/` folder.

## Step 2 — Use the *Linux* unlocker (not the Windows one)

The launcher ships unlockers for every OS. The names are confusing:

| File | What it is | Use on Linux? |
|------|-----------|---------------|
| `IronKey.exe` (top level) | **Windows** binary (`PE32`) | ❌ never runs on Linux |
| `linux/ironkey.exe` | **Linux** binary (32-bit ELF) | ✅ this one |
| `IronKey.app` | macOS app | ❌ |

If you try to run the top-level `IronKey.exe` on Linux you'll get "permission
denied" / "cannot execute" no matter what you do — it's a Windows program. Always
use `linux/ironkey.exe`.

## Step 3 — Confirm the device is seen (safe)

```bash
/media/$USER/IRONKEY/linux/ironkey.exe --show
```

Expected — something like:

```
found 1 IronKey
CDROM       Hard Drive  Generic     Serial Number
/dev/sdc    /dev/sdd    <unknown>   <unknown>
```

`CDROM` is the launcher partition; `Hard Drive` (e.g. `/dev/sdd`) is the encrypted
volume you're about to unlock. This step does **not** count against the retry
counter — run it freely to confirm everything's wired up.

No `sudo` is needed on the Kintsugi live session (the live user already has device
access).

## Step 4 — Unlock (you type the password)

```bash
/media/$USER/IRONKEY/linux/ironkey.exe
```

With a single key plugged in, no arguments are needed — it prompts for the
password. Enter it carefully (see the retry-counter warning above). On success the
encrypted volume becomes available.

## Step 5 — Open the unlocked volume

Kintsugi's desktop auto-mounts the unlocked volume (a new drive appears in the file
manager and a notification pops). If it doesn't mount automatically:

```bash
lsblk -o NAME,LABEL,FSTYPE,SIZE,MOUNTPOINT /dev/sdd     # use the 'Hard Drive' device from --show
udisksctl mount -b /dev/sdd1                            # or /dev/sdd if it has no partition table
```

## Other operations

```bash
/media/$USER/IRONKEY/linux/ironkey.exe --changepwd      # change the password
/media/$USER/IRONKEY/linux/ironkey.exe --lock           # re-lock when finished
```

When you're done, lock the key (or just safely eject — use the **Safely Remove USB
Drives** launcher on the desktop) before pulling it.

## Verification (offline)

To confirm a freshly imaged Kintsugi drive has the runtime and can unlock:

```bash
dpkg --print-foreign-architectures          # expect: i386
dpkg -l libc6:i386 | awk '/^ii/{print $2,$3}'   # expect: libc6:i386 <version>
ldd /media/$USER/IRONKEY/linux/ironkey.exe   # expect: no "not found" lines
/media/$USER/IRONKEY/linux/ironkey.exe --show   # expect: lists the device
```

All four work with **no network connection**.

## Troubleshooting

- **`bash: .../ironkey.exe: No such file or directory`** even though the file is
  there → the 32-bit runtime is missing (an older Kintsugi image built before #45).
  The file is present; its 32-bit loader isn't. On a build *with* network +
  persistence you can add it manually:

  ```bash
  sudo dpkg --add-architecture i386
  sudo apt update
  sudo apt install -y libc6:i386
  ```

  The permanent fix is to (re)build the image — the runtime is baked in by
  `legacy-tools-provision.sh`.

- **"permission denied" / "cannot execute binary file"** → you're running the
  top-level `IronKey.exe` (Windows). Use `linux/ironkey.exe` (Step 2).

- **A missing-library error from `ldd`** (a `not found` line) → that specific 32-bit
  library isn't in the image. `libc6:i386` covers the IronKey CLI; other vendor
  tools may need more (the build also adds `libstdc++6:i386` and `zlib1g:i386`
  best-effort).

## What is *not* supported

- **Qt4 GUI unlockers.** Some vendor GUIs are 32-bit Qt4; Qt4 was removed from
  Ubuntu 24.04 and is not satisfiable. The IronKey **CLI** unlocker above does not
  need it.
- **Windows-only models.** Some legacy IronKeys shipped only Windows/macOS
  unlockers (no `linux/` folder). Those can't be unlocked from Linux — use a
  Windows machine. Wine-based unlocking is **not** recommended; it's unreliable and
  can waste retry-counter attempts.
