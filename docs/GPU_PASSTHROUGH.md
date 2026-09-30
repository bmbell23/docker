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
The two queued `discard=on,ssd=1` changes on scsi0/scsi1 also apply on this stop/start (thread 015). They're harmless,
so don't be surprised by them in `qm config 101`.
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
- A fresh dump, on proxmox as root: `vzdump 101 --mode snapshot --compress zstd --storage boston_backups`
  (~106 GB, ~24 min). It won't prune the Sunday dumps: `boston_backups` is `prune-backups keep-all=1`, and only
  the scheduled job has keep-weekly=3 (Paul, `bin/proxmox storage`).
- **Proof it restores.** The best proof is the pve01 restore test (proxmox `host/PVE01.md` step 7: restore as
  VM 901 with the network link down, and see it reach a login prompt). At the very least, restore one file
  from it. This is the first host reboot in 125+ days, so don't take it without a restore you've seen work.

## Phase 1: BIOS (host reboot, every VM down ~10 min, Brandon at the keyboard)
There's no IPMI on this board, so someone has to be physically at the box.
**When:** never 01:00–04:00 (Allston copy, config backups and the pve01 jobs all read boston then) or around
Sun 21:00 (vzdump). A host reboot takes boston away from pve01 as well as from dockerhost.

**1a. Before the reboot, on proxmox as root:**
```bash
grep -o intel_iommu=on /proc/cmdline   # must print it: the kernel will ask for the IOMMU once VT-d is on
# Keep the host's sound driver off the 3070's audio function (#2 found snd_hda_intel holding 01:00.1).
grep -q 'softdep snd_hda_intel' /etc/modprobe.d/vfio-pci.conf || \
  echo 'softdep snd_hda_intel pre: vfio-pci' >> /etc/modprobe.d/vfio-pci.conf
update-initramfs -u -k all
```
Then run `prep-shutdown` in dockerhost, and on proxmox: `qm shutdown 101 --timeout 300`. Check `qm status 101` says stopped.
Then reboot the host from its console or web UI. This is the one planned host reboot, and Brandon does it himself.

**1b. At the box, in the BIOS (flying solo).**
The board is an **ASUS PRIME Z370-A**, running BIOS **0606**, from the board's 2017 launch. The latest is **3005**
(2024-01-16, a LogoFAIL patch; [ASUS BIOS page](https://www.asus.com/supportonly/prime%20z370-a/helpdesk_bios/)).
**Don't update the BIOS in this window.** 0606 already has VT-d, and a flash resets *every* setting (boot
order, SATA mode), so it would be two changes at once. If we want 3005, it gets its own ticket and window later.

Bring: a USB keyboard (plug it into a USB 2.0 port on the back), a monitor, **two** HDMI cables or one you can
move, and your phone for photos.

1. **Photograph before touching.** When the BIOS opens it's in EZ Mode. Press **F7** for Advanced Mode, then take
   a photo of every page you're about to change: *Advanced → System Agent (SA) Configuration*,
   its *Graphics Configuration* submenu, and the *Boot* tab (boot order, CSM). Those photos are your rollback.
2. **Getting in:** press **Del** (or F2) over and over from power-on. If Fast Boot skips past it, use the
   host's web UI or shell on the way down instead: `systemctl reboot --firmware-setup` (as root on proxmox) reboots
   straight into the BIOS.
3. **Advanced → System Agent (SA) Configuration → VT-d → Enabled.**
4. **Advanced → System Agent (SA) Configuration → Graphics Configuration:**
   - **Primary Display → CPU Graphics.** That's the iGPU (the 8700K's UHD 630). Leave *iGPU Memory* on Auto.
   - **iGPU Multi-Monitor → Enabled.** Without it, the board turns the iGPU off whenever a PCIe card is present.
     That's why the host has no iGPU on the PCI bus today.
5. **Also check, but don't change unless it's wrong:** *Advanced → CPU Configuration → Intel Virtualization
   Technology = Enabled* (VT-x; VMs already run, so it should be on). Leave *Above 4G Decoding* and *Resizable
   BAR* alone: 0606 has no ReBAR, and SeaBIOS/i440fx doesn't need it.
6. **F10 → Save & Exit.** The confirmation screen lists every change. It should show **only** VT-d, Primary
   Display and iGPU Multi-Monitor. If anything else is listed, cancel and fix it.
7. **Move the monitor to the motherboard HDMI** (the port on the rear I/O, not the card). From here on the host
   console lives on the iGPU, and the 3070's outputs go dark once vfio has the card. A black screen on the 3070 is
   expected, not a failure.
8. You should see the Proxmox boot menu, then the login prompt, on the motherboard HDMI. Log in as root and run 1c.

**If it won't boot to Proxmox:** go back into the BIOS, check the *Boot* tab against your photo (the `proxmox`
UEFI entry first), and fix it. **If there's no picture at all:** move the cable back to the 3070, and if that's
dark too, **Clear CMOS** (the CLRTC jumper next to the battery, per the manual) resets to defaults. Then set the
boot order again from your photos. Defaults may bring back the old display setup, which is fine: it's what the
host booted with for 125+ days.

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
**Memory first:** run `free -h` on proxmox. If swap is still in use, add `qm set 101 --memory 20480` to this same
stop/start, not a day later (Paul).
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
