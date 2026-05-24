# Test Strategy: ML-Augmented Boot & Support USB

**Project**: USB-TOOLKIT
**Version**: 1.0
**Date**: 2026-03-03
**Phase**: Elaboration

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
3. Select custom Ubuntu ISO
4. Verify shell prompt reached

**Expected**: Boot to shell in < 90 seconds
**Pass criteria**: Shell prompt with `root@ubuntu:~#`

### TC-2: Legacy BIOS Boot (QEMU)

**Requirement**: FR-1.2
**Steps**:
1. Boot QEMU without OVMF (default SeaBIOS)
2. Observe Ventoy menu appears
3. Select custom Ubuntu ISO
4. Verify shell prompt reached

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
**Precondition**: Network available, ANTHROPIC_API_KEY set
**Steps**:
1. `source ~/.config/ai-keys.env`
2. `claude --version`
3. `echo "What is 2+2?" | claude --no-input`
4. Verify response received

**Pass criteria**: Claude returns coherent response

### TC-5: Offline AI Inference Test

**Requirement**: FR-4.1 through FR-4.6
**Precondition**: No network (QEMU -nic none or cable unplugged)
**Steps**:
1. Run `start-ai.sh`
2. Verify llama-server starts on port 8080
3. `curl -s http://localhost:8080/v1/models | jq .`
4. Run interactive query:
   ```bash
   curl -s http://localhost:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"default","messages":[{"role":"user","content":"Write a bash script to check disk health with smartctl"}]}'
   ```
5. Verify coherent bash script in response
6. Test `llama-cli` interactive mode

**Pass criteria**: Model responds with relevant bash script, >5 tokens/second

### TC-6: Persistence Reboot Test

**Requirement**: FR-5.1 through FR-5.5
**Steps**:
1. Boot into custom Ubuntu with persistence
2. Create test file: `echo "persist-test" > /root/persistence-marker.txt`
3. Install a package: `apt install -y cowsay`
4. Add shell alias: `echo 'alias testpersist="echo works"' >> /root/.bashrc`
5. Reboot (via QEMU restart or physical reboot)
6. Boot again into custom Ubuntu
7. Verify:
   - `cat /root/persistence-marker.txt` → "persist-test"
   - `cowsay "hello"` → works
   - `testpersist` → "works"

**Pass criteria**: All three artifacts survive reboot

### TC-7: Supplementary ISO Boot Tests

**Requirement**: FR-8.1 through FR-8.5
**Steps**: Boot each supplementary ISO from Ventoy menu, verify:

| ISO | Verification |
|-----|-------------|
| SystemRescue | Shell prompt with `sysrescue` hostname |
| Clonezilla | Clonezilla wizard appears |
| GParted Live | GParted UI launches or CLI accessible |
| Hiren's BootCD PE | Windows PE desktop appears |
| Ubuntu Desktop | Ubuntu installer welcome screen |

**Pass criteria**: Each ISO boots to expected interface

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
5. Boot custom Ubuntu ISO

**Pass criteria**: Successful boot with Secure Boot enabled after MOK enrollment

### TC-11: AI Model Auto-Selection

**Requirement**: FR-4.7
**Steps**:
1. Boot QEMU with `-m 8G` (8GB RAM)
2. Run `start-ai.sh`
3. Verify Phi-4-mini selected (not Qwen 7B)
4. Boot QEMU with `-m 16G`
5. Run `start-ai.sh`
6. Verify Qwen2.5-Coder 7B selected

**Pass criteria**: Correct model selected based on available RAM

### TC-12: Aider Offline Integration

**Requirement**: FR-4.5
**Steps**:
1. Boot with no network
2. Run `start-ai.sh` (starts llama-server)
3. `aider --no-auto-commits`
4. Ask Aider to create a simple script
5. Verify Aider generates code using local API

**Pass criteria**: Aider produces functional code via local llama-server

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
| Iteration 2 (Cubic ISO build) | TC-3, TC-1 | QEMU |
| Iteration 3 (AI stack integration) | TC-4, TC-5, TC-11, TC-12 | QEMU |
| Iteration 4 (Persistence + Fleet) | TC-6, TC-8 | QEMU |
| Iteration 5 (Physical validation) | TC-1, TC-3, TC-5, TC-6, TC-10 | ref-host-1 + ref-host-2 |
| Iteration 6 (Full suite) | All | Physical + QEMU |
