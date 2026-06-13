# Test Strategy: Kintsugi USB

**Project**: Kintsugi USB
**Version**: 1.1 (reconciled 2026-06-13 to the current ADR-008 design)
**Phase**: Construction

---

## 1. Test Approach

Testing follows two phases:
1. **Virtual validation** (QEMU) — fast iteration during construction
2. **Physical validation** — final acceptance on fleet hardware

Each test case maps to requirements via the traceability matrix in `requirements.md`.

---

## 2. Test Environment

### Virtual (QEMU)

```bash
# UEFI boot test
qemu-system-x86_64 \
  -enable-kvm \
  -m 8G \
  -bios /usr/share/OVMF/OVMF_CODE.fd \
  -drive file=/dev/sdX,format=raw,if=virtio \
  -net nic -net user

# Legacy BIOS boot test
qemu-system-x86_64 \
  -enable-kvm \
  -m 8G \
  -drive file=/dev/sdX,format=raw,if=virtio \
  -net nic -net user

# Offline test (no network)
qemu-system-x86_64 \
  -enable-kvm \
  -m 16G \
  -bios /usr/share/OVMF/OVMF_CODE.fd \
  -drive file=/dev/sdX,format=raw,if=virtio \
  -nic none
```

### Physical Fleet Hosts

| Host | CPU | RAM | Boot Mode | Test Priority |
|------|-----|-----|-----------|---------------|
| ref-host-1 | i9-14900KF | 64 GB | UEFI + Secure Boot | HIGH |
| ref-host-2 | i7-12700H | 32 GB | UEFI + Secure Boot | HIGH |
| ref-host-3 | i7-8700K | 32 GB | UEFI | MEDIUM |
| ref-host-4 | i7-8700K | 32 GB | UEFI | LOW (container host, rarely rebooted) |

---

## 3. Test Cases

### TC-1: UEFI Boot (QEMU)

**Requirement**: FR-1.1
**Steps**:
1. Boot QEMU with OVMF firmware pointing to USB device
2. Observe Ventoy menu appears
3. Select the Kintsugi ISO
4. Verify the Xubuntu (XFCE) live session / shell prompt reached

**Expected**: Boot to desktop/shell in < 90 seconds
**Pass criteria**: Xubuntu live session reaches a usable shell

### TC-2: Legacy BIOS Boot (QEMU)

**Requirement**: FR-1.2
**Steps**:
1. Boot QEMU without OVMF (default SeaBIOS)
2. Observe Ventoy menu appears
3. Select the Kintsugi ISO
4. Verify the Xubuntu live session / shell prompt reached

**Expected**: Boot to shell in < 90 seconds
**Pass criteria**: Shell prompt accessible

### TC-3: Rescue Tool Presence

**Requirement**: FR-6.1 through FR-6.10
**Steps**:
Run verification script:
```bash
#!/bin/bash
TOOLS=(
  smartctl nvme testdisk photorec ddrescue
  fsck.ext4 xfs_repair btrfs
  nmap tcpdump mtr dig iperf3 curl arp-scan
  gparted parted fdisk gdisk
  grub-install efibootmgr
  htop iotop lsof strace dmidecode inxi lshw
  tmux vim nano rsync pv jq git
  python3 pip3 node
)
MISSING=()
for tool in "${TOOLS[@]}"; do
  command -v "$tool" &>/dev/null || MISSING+=("$tool")
done
if [ ${#MISSING[@]} -eq 0 ]; then
  echo "PASS: All ${#TOOLS[@]} tools present"
else
  echo "FAIL: Missing tools: ${MISSING[*]}"
fi
```

**Pass criteria**: All tools found in PATH

### TC-4: Claude Code Online Test

**Requirement**: FR-3.1, FR-3.2
**Precondition**: Network available; signed in to Claude Code (post-flash)
**Steps**:
1. Sign in to Claude Code (its login flow; auth lives in persistence, never baked)
2. `claude --version`
3. `echo "What is 2+2?" | claude --no-input`
4. Verify response received

**Pass criteria**: Claude returns coherent response

### TC-5: Offline AI Inference Test

**Requirement**: FR-4.1 through FR-4.6
**Precondition**: A model has been pulled into persistence (e.g. `kintsugi-models pull qwen3.5:4b`); then no network (QEMU -nic none or cable unplugged)
**Steps**:
1. Run `start-ai` (launches Ollama; it ships stopped)
2. Verify Ollama is up and the model is present: `ollama list`
3. `curl -s http://localhost:11434/v1/models | jq .`
4. Run an interactive query:
   ```bash
   ollama run qwen3.5:4b "Write a bash script to check disk health with smartctl"
   ```
5. Verify a coherent bash script in the response

**Pass criteria**: Model responds with a relevant bash script, > 5 tokens/second

### TC-6: Persistence Reboot Test

**Requirement**: FR-5.1 through FR-5.5
**Steps**:
1. Boot the Kintsugi (Xubuntu) live session with persistence
2. Create test file: `echo "persist-test" > /root/persistence-marker.txt`
3. Install a package: `apt install -y cowsay`
4. Add shell alias: `echo 'alias testpersist="echo works"' >> /root/.bashrc`
5. Reboot (via QEMU restart or physical reboot)
6. Boot again into the Kintsugi live session
7. Verify:
   - `cat /root/persistence-marker.txt` → "persist-test"
   - `cowsay "hello"` → works
   - `testpersist` → "works"

**Pass criteria**: All three artifacts survive reboot

### TC-7: Supplementary ISO Boot Tests

**Requirement**: FR-8.1 through FR-8.5
**Precondition**: The optional rescue ISOs have been added to the data partition (#35)
**Steps**: Boot each added supplementary ISO from the Ventoy menu, verify:

| ISO | Verification |
|-----|-------------|
| SystemRescue | Shell prompt with `sysrescue` hostname |
| Clonezilla | Clonezilla wizard appears |
| GParted Live | GParted UI launches or CLI accessible |
| Memtest86+ | Memtest86+ memory test screen appears |
| (any operator-added installer ISO) | That ISO's installer/welcome screen appears |

**Pass criteria**: Each added ISO boots to its expected interface

### TC-8: Fleet Integration

**Requirement**: FR-7.1 through FR-7.3
**Steps**:
1. Boot on ref-host-2 (or QEMU with network)
2. `ssh ref-host-1` → verify key-based auth works
3. `ls /data/scripts/` → verify fleet scripts present
4. `grep ref-host-1 /etc/hosts` → verify fleet hostnames

**Pass criteria**: SSH connects without password, scripts and hosts present

### TC-9: Cross-Platform Data Access

**Requirement**: FR-9.1
**Steps**:
1. Boot Windows VM (or use windev VM on ref-host-1)
2. Insert USB or passthrough USB to VM
3. Verify exFAT data partition mounts and files readable
4. Write a test file from Windows
5. Boot Linux and verify file readable

**Pass criteria**: File round-trips between Windows and Linux

### TC-10: Secure Boot Test

**Requirement**: FR-1.5
**Steps**:
1. Boot on ref-host-1 with Secure Boot enabled
2. Ventoy MOK enrollment prompt appears on first boot
3. Enroll MOK
4. Reboot → Ventoy menu appears
5. Boot the Kintsugi ISO

**Pass criteria**: Successful boot with Secure Boot enabled after MOK enrollment

### TC-11: User-Driven Model Loading

**Requirement**: FR-4.5, FR-4.6 (RAM-based GGUF auto-select is **RETIRED** per ADR-005)
**Steps**:
1. On a fresh boot, confirm the base image ships **no** model weights (`ollama list` is empty)
2. `kintsugi-models pull qwen3.5:4b` (or `ollama pull`) — populates `/data/ollama/models` in persistence
3. Reboot; verify the model persists (`ollama list` still shows it)
4. `start-ai` surfaces the user-loaded model

**Pass criteria**: No weights baked into the image; a user-pulled model loads and survives reboot

### TC-12: Aider Offline Integration

**Requirement**: FR-4.10
**Precondition**: A model pulled into persistence; no network
**Steps**:
1. Run `start-ai` (starts Ollama)
2. Point Aider at the local Ollama endpoint (`OPENAI_API_BASE=http://localhost:11434/v1`)
3. `aider --no-auto-commits`
4. Ask Aider to create a simple script
5. Verify Aider generates code using the local Ollama API

**Pass criteria**: Aider produces functional code via the local Ollama endpoint

---

## 4. Acceptance Criteria Summary

| Category | Must Pass | Should Pass | Nice to Have |
|----------|-----------|-------------|--------------|
| Boot (UEFI) | TC-1, TC-10 | TC-7 all ISOs | — |
| Boot (BIOS) | TC-2 | — | — |
| Tools | TC-3 | — | — |
| AI (Online) | TC-4 | — | — |
| AI (Offline) | TC-5 | TC-11, TC-12 | — |
| Persistence | TC-6 | — | — |
| Fleet | — | TC-8 | — |
| Cross-platform | — | TC-9 | — |

**Construction exit criteria**: All "Must Pass" tests green on at least one physical fleet host (ref-host-2 or ref-host-1) and QEMU.

---

## 5. Test Execution Schedule

| Phase | Tests | Method |
|-------|-------|--------|
| Iteration 1 (Ventoy setup) | TC-1, TC-2 | QEMU |
| Iteration 2 (remaster ISO build, ADR-008) | TC-3, TC-1 | QEMU |
| Iteration 3 (AI stack integration) | TC-4, TC-5, TC-11, TC-12 | QEMU |
| Iteration 4 (Persistence + Fleet) | TC-6, TC-8 | QEMU |
| Iteration 5 (Physical validation) | TC-1, TC-3, TC-5, TC-6, TC-10 | ref-host-1 + ref-host-2 |
| Iteration 6 (Full suite) | All | Physical + QEMU |
