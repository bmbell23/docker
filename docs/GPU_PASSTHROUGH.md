# RTX 3070 passthrough to dockerhost (VM 101): the whole runbook

Ticket: docker#2. Scoping: the #2 issue body (Bianca, 2026-09-28) and agent-bus thread 014 (Paul).
Host-side steps are Paul's (bmbell23/proxmox); guest-side steps are Dakota's. **Brandon runs every
command marked root.** No agent has root on the hypervisor, by design.

**One change per window.** Each phase below is its own window, with its own check and rollback. Don't
start a phase until the one before it has been verified. If a check fails, stop, roll back that phase,
and tell Paul (host) or Dakota (guest) before trying anything else.

## Facts this plan rests on (as of 2026-09-30)
| What | Value | Source |
|---|---|---|
| Host | `proxmox`, PVE 9.0.3, i7-8700K, ASUS PRIME Z370-A (BIOS 0606), UEFI, 31 GB RAM | #2 |
| GPU | `01:00.0` RTX 3070 `[10de:2484]`, `01:00.1` HDMI audio `[10de:228b]` | #2 |
| Already on the host | `intel_iommu=on` in grub, vfio modules, `/etc/modprobe.d/vfio-pci.conf` with both ids, nouveau/nvidia blacklisted | #2 |
| **Why the last try "bricked"** | VT-d is off in the BIOS: `/sys/kernel/iommu_groups` has 0 groups. With no IOMMU, any `hostpci` line stops VM 101 from starting | #2 |
| VM 101 | SeaBIOS, i440fx, 24 GB, CPU type `x86-64-v2-AES` (no AVX), `onboot: 1`, guest agent on | thread 014/015 |
| Guest | Ubuntu 25.04, kernel 6.14.0-37, `nvidia-dkms-570` built for that kernel, `nvidia-container-toolkit` 1.18.2, Docker has **only runc** | #2, `docker info` |
| Guest root disk | 101G, **90% used, 9.7G free** | `df -h /`, 2026-09-30 |
| `/mnt/docker` | 196G, 147G free: models and images go here | `df -h /mnt/docker` |

## Phase 0: prerequisites (no GPU work yet)
These come first, each in its own window. The GPU work waits until all of them are done.

### 0a. Free space on dockerhost's root disk (Dakota; no downtime)
The NVIDIA/CUDA images and any driver rebuild need headroom, and a full root disk is how Jan 7 started.
Target: **at least 20G free on `/`** before phase 2. Dakota finds what's eating it and proposes the moves
(no prune). Brandon approves anything that deletes.

### 0b. CPU type `host` (VM 101 stop/start, ~2 min; thread 014)
Wrap it in the shutdown runbook (`docs/SHUTDOWN_RUNBOOK.md`): `prep-shutdown`, then on proxmox as root:
```bash
qm shutdown 101 --timeout 300
qm status 101                       # stopped
qm set 101 --cpu host
qm start 101
qm agent 101 ping && echo agent-ok
```
A reboot *inside* the guest doesn't pick up the new CPU type; it needs this stop/start.
**Check** (in dockerhost): `grep -o -w avx2 /proc/cpuinfo | head -1` prints `avx2`, then `verify-boot` says CLEAN BOOT.
**Rollback:** `qm set 101 --delete cpu`, then stop/start again.

### 0c. Updates (separate windows, Paul's host and Dakota's guest)
- **Host:** the ~323 pending updates / PVE 9.1 go in their own window, with their own reboot. **Never in
  the same window as the BIOS change**, so if something breaks we know which change did it.
- **Guest:** if an Ubuntu update brings a new kernel, check that the NVIDIA module was rebuilt for it
  **before** GPU day: `dkms status` must show `nvidia/570…` as `installed` for the kernel in `uname -r`.

### 0d. Make docker wait for /mnt/boston (Brandon's OK, it's /etc)
The GPU window reboots the **host**, so boston (served by the host's Samba) disappears and comes back
together with VM 101. That's exactly the race described under "Known gap" in `docs/SHUTDOWN_RUNBOOK.md`.
Apply that drop-in before phase 1, or be ready to fix the mounts by hand after the reboot.

### 0e. A backup you've actually restored (Paul + Peter)
- A fresh `vzdump 101` (the weekly one on boston is ~106 GB, ~24 min).
- **Proof it restores.** The best proof is the pve01 restore test (proxmox `host/PVE01.md` step 7: restore as
  VM 901 with the network link down, and see it reach a login prompt). At the very least, restore one file
  from it. This is the first host reboot in 125+ days, so don't take it without a restore you've seen work.

## Phase 1: BIOS (host reboot, every VM down ~10 min, Brandon at the keyboard)
There's no IPMI on this board, so someone has to be physically at the box. Plug a monitor into the
**motherboard** HDMI as well as the 3070.

**1a. Before the reboot, on proxmox as root:**
```bash
# Keep the host's sound driver off the 3070's audio function (#2 found snd_hda_intel holding 01:00.1).
grep -q 'softdep snd_hda_intel' /etc/modprobe.d/vfio-pci.conf || \
  echo 'softdep snd_hda_intel pre: vfio-pci' >> /etc/modprobe.d/vfio-pci.conf
update-initramfs -u -k all
```
Then run `prep-shutdown` in dockerhost, and on proxmox: `qm shutdown 101 --timeout 300`. Check `qm status 101` says stopped.
Then reboot the host from its console or web UI. This is the one planned host reboot, and Brandon does it himself.

**1b. In the BIOS** (F2/Del at boot; ASUS menu names, so check them on screen):
- Advanced → System Agent (SA) Configuration → **VT-d = Enabled**.
- Advanced → System Agent (SA) Configuration → Graphics Configuration → **Primary Display = CPU Graphics**
  (iGPU). Also turn **iGPU Multi-Monitor = Enabled** so the iGPU stays on with the 3070 installed.
- Save and exit.

**1c. Check, on proxmox as root, before starting VM 101 on anything new:**
```bash
ls /sys/class/iommu                 # dmar0 (and maybe dmar1): IOMMU is on
find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 | wc -l   # > 0
lspci -nnk -s 01:00                 # both functions: "Kernel driver in use: vfio-pci"
for d in /sys/bus/pci/devices/0000:01:00.*; do echo "$d -> group $(basename $(readlink $d/iommu_group))"; \
  ls $(readlink -f $d/iommu_group)/devices; done   # the group holds 01:00.0/.1, plus at most the PCIe root port
```
VM 101 comes back on its own (`onboot: 1`) with **no `hostpci` yet**, so this reboot changed only the BIOS.
Run `verify-boot` in dockerhost.
**Rollback:** VT-d off and Primary Display back to its old value (no VM config has changed yet).
**If the group holds other devices** (the SATA controller, the NIC): stop. Passing it through would take
those devices from the host. Tell Paul before doing anything else.

## Phase 2: give the GPU to VM 101 (VM stop/start, ~2 min)
On proxmox as root:
```bash
qm shutdown 101 --timeout 300 && qm status 101
qm set 101 --hostpci0 0000:01:00    # both functions; keep i440fx + SeaBIOS
qm start 101
qm agent 101 ping && echo agent-ok
```
- **Keep i440fx/SeaBIOS.** For compute only, we don't need q35/OVMF, and moving to q35 renames `ens18`, which breaks
  netplan's static IP. That looks like a brick even though it isn't.
- **Memory:** passthrough pins all 24 GB of VM 101 in host RAM. The host has 31 GB and already had 5.2 GB in
  swap (`bin/proxmox health`, 09-29). Paul watches host memory for a day. The fallback is `qm set 101 --memory 20480`
  plus a stop/start.

**Check** (in dockerhost): `lspci | grep -i nvidia` shows the card, and `nvidia-smi` shows an RTX 3070. Then `verify-boot`.
**Rollback:** `qm shutdown 101 && qm set 101 --delete hostpci0 && qm start 101`.
**If VM 101 won't start:** run `qm start 101` from the proxmox shell to see the error, then roll back.

## Phase 3: Docker's NVIDIA runtime (dockerd restart, every container bounces; its own window)
In dockerhost:
```bash
~/projects/docker/scripts/maintenance/prep-shutdown.sh   # snapshot + DB dumps; wait for SAFE
[ -f /etc/docker/daemon.json ] && sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak-$(date +%F)
sudo nvidia-ctk runtime configure --runtime=docker      # writes the nvidia runtime into /etc/docker/daemon.json
sudo systemctl restart docker
docker info --format '{{json .Runtimes}}' | grep -o nvidia   # nvidia
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi
~/projects/docker/scripts/maintenance/verify-boot.sh
```
- `unless-stopped` containers come back on their own after a dockerd restart. `verify-boot` proves it,
  and checks for stale DNAT rules.

**Rollback:** restore `daemon.json` from the `.bak` (or delete it if there was none before), then `sudo systemctl restart docker`.

## Phase 4: use it (separate ticket)
A local image service (ComfyUI or diffusers, with models on `/mnt/docker`) for MuseForge. That's Molly's ask
in thread 014, and it gets its own ticket and port once phases 0–3 are green.

## Who does what
| Phase | Runs it | Verifies |
|---|---|---|
| 0a space | Dakota proposes, Brandon approves deletes | Dakota (`df`) |
| 0b CPU type | Brandon (proxmox root) | Dakota (`/proc/cpuinfo`, `verify-boot`) |
| 0c updates | Brandon | Paul (host), Dakota (guest `dkms status`) |
| 0d docker waits for boston | Brandon (/etc) | Dakota |
| 0e backup + restore | Brandon | Paul, Peter |
| 1 BIOS + host reboot | Brandon, at the box | Paul (IOMMU, vfio), Dakota (`verify-boot`) |
| 2 hostpci | Brandon (proxmox root) | Dakota (`nvidia-smi`), Paul (host memory) |
| 3 Docker runtime | Brandon (guest sudo) | Dakota (`docker run --gpus all`, `verify-boot`) |
