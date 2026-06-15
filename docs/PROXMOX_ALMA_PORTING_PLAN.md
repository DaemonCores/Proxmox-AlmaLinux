# Proxmox VE Porting Plan for AlmaLinux

## 1. Executive Summary

**Vision**: Deliver a single, integrated web UI for KVM virtualisation, LXC containers, ZFS storage, firewall management, and network configuration on AlmaLinux — matching the Proxmox VE user experience without requiring Debian.

**Approach**: Port the Proxmox VE (PVE) userspace packages to RPM format, bypassing the `pve-kernel` entirely by using the stock AlmaLinux kernel with OpenZFS DKMS modules. The porting effort leverages two existing reference implementations: the `proxmox-nixos` project (which proves PVE core is portable — 50+ Nix expressions packaging all major PVE components) and the project's own `scripts/` directory (which provides a proven Bash+Docker+YAML CI pipeline for multi-format package conversion, originally derived from the `astralemu-packages` fork).

**Estimated effort**: 3–5 months for a single experienced developer, assuming familiarity with RPM packaging, Perl, and Proxmox internals.

**Key enablers**:
- `proxmox-nixos` (1.3k stars) — complete package graph and build orchestration reference
- Project `scripts/` — reusable CI/CD plumbing (30–40% of infrastructure scripts, originally from `astralemu-packages`)
- AlmaLinux EL10 kernel — avoids the entire `pve-kernel` porting effort

## 2. Background & Motivation

### 2.1 Why not Debian/Proxmox natively?

The user maintains an AlmaLinux-based homelab and needs to stay on an EL distribution for compatibility with existing infrastructure, SELinux policies, and RHEL-derived tooling. Running Proxmox natively would require Debian, which is incompatible with the rest of the environment.

### 2.2 Why not OpenNebula?

OpenNebula is a mature virtualisation platform available on EL distros, but it lacks:
- Native ZFS management in the web GUI (ZFS pool creation, dataset management, snapshots from GUI)
- Docker/LXC integration comparable to PVE's unified container management
- The "single pane of glass" simplicity of PVE's web UI for both VMs and containers

### 2.3 Why not build a UI from scratch?

Building an equivalent management UI from scratch would take 4–6 months for a minimum viable product, incur high technical debt, and require ongoing maintenance of a custom web framework. PVE's web UI (ExtJS-based) is already complete and battle-tested.

### 2.4 The proxmox-on-nix proof

The `proxmox-nixos` project (https://github.com/SaumonNet/proxmox-nixos) proves that Proxmox VE's core is portable. It contains ~50 Nix expressions packaging every significant PVE component: `pve-manager`, `pve-qemu-server`, `pve-cluster`, `pve-storage`, `pve-firewall`, Perl modules, helper libraries, and the web UI. Critically, it does **not** package `pve-kernel` — it uses the standard NixOS kernel instead. This validates the "skip pve-kernel, use EL kernel" strategy.

## 3. Source Analysis

### 3.1 proxmox-nixos (Knowledge Blueprint)

**What it covers** — the complete PVE userspace package graph (sourced from `pkgs/default.nix`):

| Category | Packages |
|---|---|
| **Perl modules** | `authenpam`, `datadumper`, `digestsha`, `findbin`, `iosocketip`, `mimebase32`, `mimebase64`, `netsubnet`, `posixstrptime`, `socket`, `termreadline`, `testharness`, `uuid` |
| **Helper libraries** | `extjs`, `fonts-font-logos`, `markedjs`, `qrcodejs`, `perlmod`, `termproxy`, `unifont_hex`, `vncterm`, `cstream` |
| **Core PVE packages** | `pve-common`, `pve-access-control`, `pve-apiclient`, `pve-cluster`, `pve-storage`, `pve-firewall`, `pve-guest-common`, `pve-ha-manager`, `pve-http-server`, `pve-manager`, `pve-network`, `pve-qemu-server` |
| **PVE ecosystem** | `proxmox-acme`, `proxmox-backup-qemu`, `proxmox-i18n`, `proxmox-widget-toolkit`, `proxmox-wasm-builder` |
| **QEMU** | `pve-qemu` (QEMU with Proxmox patches applied from `debian/patches/series`) |
| **Container/VM** | `pve-container`, `pve-edk2-firmware`, `pve-novnc`, `pve-xtermjs`, `pve-yew-mobile-gui` |
| **Rust components** | `pve-rs`, `pve-rados2` |
| **Linstor** | `linstor-api-py`, `linstor-client`, `linstor-proxmox`, `linstor-server` |
| **Infrastructure** | `mkRegistry` (NixOS module integration), `nixmoxer`, `pve-update`, `pve-update-script` |
| **Documentation** | `pve-docs` |

**What it does NOT cover**:
- `pve-kernel` — uses the standard NixOS kernel instead
- `pve-backup-server` (the full backup server, only the client library is packaged)
- Ceph integration is present but optional (`enableLinstor` flag)

**Key insight**: the Nix expressions document every `debian/patches/series` patch application (visible in `pve-qemu/default.nix`), every hardcoded `/usr` path that needs sed replacement (visible in `postFixup` blocks of `pve-manager`, `pve-common`, `pve-storage`), and every dependency that must be wrapped or substituted. These sed commands form the **Debian-to-RPM path mapping** that this porting plan will adapt.

**Transposability to RPM**:
- **High** for the package dependency graph (direct 1:1 mapping)
- **Medium** for the build system (Nix's `callPackage` and `stdenv.mkDerivation` must be translated to RPM specfiles + Docker build environments)
- **Low** for runtime integration (NixOS module system vs systemd units on AlmaLinux)

### 3.2 Project CI/CD & Packaging Scripts

**Location**: `/home/gabriel/GIT/HomeLab/scripts/` (local, within this project)

**What is reusable**:

| Component | Path | Reuse estimate |
|---|---|---|
| RPM build script | `scripts/pkg-build-rpm.sh` | **High** — 90% reusable. Handles specfile generation, dependency mapping, architecture conversion, scriptlet translation (deb/rpm/pacman → rpm), systemd unit detection, ldconfig, and conffiles. Already supports AlmaLinux/Fedora target. |
| Dependency resolver | `scripts/resolve-deps.sh` | **High** — 85% reusable. Recursive dependency resolution across distros, version compatibility checking, batch Docker-based queries, multi-format dependency name mapping. |
| Dependency map | `scripts/dep-map.conf` | **High** — 70% reusable as starting point. Contains 677 lines of `deb_name rpm:rpm_name pac:pac_name` mappings covering C runtime, crypto, networking, X11, Wayland, Qt, GTK, audio, video codecs, boost, emulator-specific libs. Will need Proxmox-specific additions (Perl modules, corosync, libqb, etc.). |
| Cross-pkg helpers | `scripts/cross-pkg-helpers.sh` | **Medium** — provides `relocate_lib_paths` and `translate_script` used by `pkg-build-rpm.sh`. |
| CI workflow structure | `.github/workflows/` | **Medium** — GitHub Actions YAML with Docker-based multi-arch build, 4-chain bin-packing pattern. The workflow structure is reusable but package definitions need full replacement. |
| Package definition format | `packages.yml` | **Medium** — YAML format with `id`, `version_source`, `build_time`, `power_arm`, `power_amd`, `true_arm`, `true_amd`, `depends_on`. The format itself is reusable; all package entries will be replaced. |
| Extract script | `scripts/pkg-extract.sh` | **High** — extracts any format (deb/rpm/pacman) into an intermediate `.pkg.tar` directory with `meta/` and `root/` subdirs. This is the format consumed by `pkg-build-rpm.sh`. |

**What is NOT reusable**:

| Component | Reason |
|---|---|
| `emulators.yml`, `devices.yml` | Gaming emulator and device-specific builds — irrelevant to PVE |
| Kernel build scripts (`kernel-helpers.sh`, `kernel-amd64-*`) | PVE port uses stock EL kernel, not custom kernel builds |
| `distros.yml` | Defines Ubuntu/Debian/Fedora/Arch targets — will need AlmaLinux addition but the file structure is simple |
| `perf-libs` package | GPU/Mesa performance libs — not needed for PVE |
| `setperf`, `astralemu-deps-repo` | Device-specific meta-packages — irrelevant (from the original `astralemu-packages` fork, not part of PVE porting) |

**Estimated reuse**: 30–40% of infrastructure plumbing (build scripts, dependency resolution, CI patterns). The package definitions themselves are 0% reusable (completely different software), but the build pipeline architecture is proven working.

**Key insight**: the project's `scripts/` pipeline uses an intermediate `.pkg.tar` format (a directory with `meta/` for metadata and `root/` for filesystem contents). Every source format (deb, rpm, pacman) is first extracted to `.pkg.tar`, then converted to the target format. This "extract once, convert many" pattern is directly applicable to PVE's Debian packages.

### 3.3 Enterprise Linux Kernel Strategy

**Decision**: do NOT port `pve-kernel`.

**Approach**: Use the stock AlmaLinux kernel (`kernel` or `kernel-ml` from ELRepo for newer versions) plus `zfs-dkms` (OpenZFS DKMS module available from EPEL or the OpenZFS repository).

**Rationale**:
- `proxmox-nixos` does not package `pve-kernel` either, and the PVE core works fine on a standard kernel
- The EL kernel already includes KVM, virtio, vhost-net, bridge, VLAN, and most virtualisation features as modules
- ZFS on Linux (OpenZFS) is mature and well-maintained on EL distributions via DKMS
- Avoiding the kernel port eliminates the most fragile and hardest-to-maintain component

**Trade-offs**:

| Aspect | PVE kernel | EL kernel + ZFS DKMS |
|---|---|---|
| KSM tuning | Custom `ksm` parameters in pve-kernel | Manual sysctl tuning required |
| Signed modules | Built-in signing | Must use DKMS (unsigned) or sign manually |
| Maintenance per PVE release | Rebase entire kernel | Just update DKMS on kernel update |
| Complexity | Very high | Low |
| Proxmox-specific patches | Included | Must check if critical (unlikely for most) |

**Risk mitigation**: test ZFS pool creation/import via GUI early in Phase 5.

## 4. Porting Architecture

### 4.1 Package Dependency Graph

Based on `proxmox-nixos/pkgs/default.nix` and the `propagatedBuildInputs`/`perlDeps` in each package, the build order is:

```
Layer 0 — Perl leaf modules (no PVE deps)
├── authenpam
├── datadumper
├── digestsha
├── findbin
├── iosocketip
├── mimebase32
├── mimebase64
├── netsubnet
├── posixstrptime
├── socket
├── termreadline
├── testharness
└── uuid

Layer 1 — Helper libraries (no PVE deps)
├── extjs
├── fonts-font-logos
├── markedjs
├── qrcodejs
├── perlmod
├── termproxy
├── unifont_hex
├── vncterm
└── cstream

Layer 2 — PVE foundation (depends on Layer 0 + 1)
├── proxmox-widget-toolkit  (JS/CSS toolkit, no PVE deps)
├── proxmox-i18n             (translations, no PVE deps)
├── pve-apiclient            (API client, minimal deps)
├── proxmox-acme             (ACME client, Perl deps)
└── proxmox-backup-qemu      (backup client for QEMU)

Layer 3 — Core Perl libraries (depends on Layer 2)
├── pve-common               (depends on: 25+ CPAN modules + proxmox-backup-client)
└── pve-rs                   (Rust component, minimal deps)

Layer 4 — PVE core services (depends on Layer 3)
├── pve-access-control       (depends on: pve-common, pve-apiclient)
├── pve-cluster               (depends on: pve-access-control, pve-apiclient, pve-rs, corosync, fuse, sqlite)
├── pve-http-server           (depends on: pve-common)
└── pve-rados2               (depends on: pve-common, librados)

Layer 5 — PVE feature modules (depends on Layer 4)
├── pve-storage               (depends on: pve-cluster, pve-rados2, ceph, lvm2, nfs-utils, etc.)
├── pve-firewall              (depends on: pve-access-control, pve-cluster, pve-network, pve-rs, iptables, ipset)
├── pve-guest-common          (depends on: pve-common)
├── pve-ha-manager            (depends on: pve-cluster, pve-common)
└── pve-network               (depends on: pve-common)

Layer 6 — PVE compute (depends on Layer 5)
├── pve-qemu                  (QEMU + PVE patches, depends on: proxmox-backup-qemu)
├── pve-qemu-server           (depends on: pve-common, pve-storage, pve-guest-common, pve-qemu)
└── pve-container              (depends on: pve-common, pve-storage, pve-guest-common, lxc)

Layer 7 — PVE manager (depends on all above)
└── pve-manager               (depends on: EVERYTHING above)
    ├── pve-docs
    ├── pve-novnc
    ├── pve-xtermjs
    └── pve-yew-mobile-gui
```

### 4.2 Build System Design

**Intermediate format**: `.pkg.tar` directory (from project `scripts/`)
- Contains `meta/` (name, version, arch, description, maintainer, depends, provides, conflicts, replaces, scripts/) and `root/` (filesystem payload)
- Enables format-agnostic processing: extract once, convert to any target

**Conversion pipeline**: `.pkg.tar` → `.rpm` via `pkg-build-rpm.sh`
- Handles arch mapping (amd64 → x86_64, all → noarch)
- Handles dependency name mapping via `dep-map.conf` (Debian name → RPM name)
- Handles scriptlet translation (deb preinst/postinst/prerm/postrm → RPM %pre/%post/%preun/%postun)
- Handles systemd unit detection and preset/disable injection
- Handles ldconfig for shared libraries
- Handles conffiles → %config(noreplace) mapping

**Docker base image**: `almalinux:latest` + build tools
```dockerfile
FROM almalinux:10
RUN dnf install -y \
    @development-tools \
    rpm-build \
    rpmdevtools \
    createrepo_c \
    python3 \
    perl \
    meson \
    ninja-build \
    pkg-config \
    git \
    wget \
    curl \
    && dnf clean all
```

**CI**: GitHub Actions with a multi-job pipeline inspired by `proxmox-nixos` and the project's own `scripts/`:
1. **resolve-deps**: Query AlmaLinux repos for dependency availability
2. **build-perl-deps**: Build Layer 0 Perl modules
3. **build-helpers**: Build Layer 1 helper libraries
4. **build-core**: Build Layers 2–5 (foundation + core + feature modules)
5. **build-compute**: Build Layer 6 (QEMU, qemu-server, container)
6. **build-manager**: Build Layer 7 (pve-manager — the final package)
7. **integration-test**: Install all RPMs on a fresh AlmaLinux VM, start pveproxy, run smoke tests

Each job runs in a Docker container based on the image above. Artifacts (built RPMs) are passed between jobs via GitHub Actions artifacts or a shared repo.

**Source acquisition**: each PVE package is fetched from `git://git.proxmox.com/git/<package>.git` at a pinned commit (matching the version targeted). The `debian/patches/series` file in each repo lists the PVE-specific patches to apply.

### 4.3 Kernel & Storage

**Kernel**: stock AlmaLinux `kernel` (6.12-based for EL10) or `kernel-ml` from ELRepo for newer versions. The EL10 kernel provides all required virtualisation features natively. EL10's 6.12 kernel already includes:
- KVM (full virtualisation)
- virtio, virtio-scsi, virtio-net, virtio-balloon, virtio-rng
- vhost-net, vhost-scsi
- bridge, VLAN, macvlan, ipvlan
- OVS kernel module
- cgroups v2, namespaces (for LXC)

**ZFS**: `zfs-dkms` from the OpenZFS repository (https://openzfs.github.io/openzfs-docs/). Install via:
```bash
dnf install -y https://zfsonlinux.org/epel/zfs-release-3-0.el10.noarch.rpm
dnf install -y zfs-dkms zfs
```

> **⚠️ Known issue (June 2026)**: OpenZFS 2.2.9 on EL10 has a CPU ISA level mismatch on x86-64-v2 systems (OpenZFS issue #18665). The DKMS module loads fine, but `zpool import` fails with "CPU ISA level is lower than required." Workaround: rebuild the userland RPMs locally from source. This is expected to be resolved in a future OpenZFS release.

**Storage backend**: ZFS datasets (local). Ceph can be added later as an optional dependency — `proxmox-nixos` already makes it optional via `enableLinstor`.

## 5. Implementation Phases

### Phase 1: Bootstrap (Weeks 1–2)

**Goal**: Create the repo structure, adapt CI scripts, build first Perl module RPM.

| Task | Details |
|---|---|
| Create repo structure | `packages/`, `scripts/`, `.github/workflows/` |
| Copy reusable scripts | `pkg-build-rpm.sh`, `pkg-extract.sh`, `cross-pkg-helpers.sh`, `resolve-deps.sh`, `dep-map.conf` — already present in project `scripts/` |
| Create AlmaLinux dep-map | Extend `dep-map.conf` with Proxmox-specific Debian→RPM mappings (Perl modules, corosync, libqb, fuse3, etc.) |
| Create `packages.yml` | Based on the dependency graph in §4.1, list all packages with `id`, `version_source`, `build_time`, `depends_on` |
| Build Docker image | `almalinux:10` + dev tools + Perl 5.40 + meson + RPM build tools |
| CI skeleton | GitHub Actions workflow with build, test, and publish jobs |
| Build first Perl module | Pick `uuid` or `digestsha` (leaf, no deps) — validate end-to-end: fetch from CPAN → extract to `.pkg.tar` → convert to `.rpm` → install on AlmaLinux VM |

**Deliverable**: One Perl module RPM installable on AlmaLinux, CI pipeline green.

### Phase 2: Leaf Packages (Weeks 3–5)

**Goal**: Build all Layer 0 (Perl leaf modules) and Layer 1 (helper libraries) packages.

| Task | Details |
|---|---|
| Build all 13 Perl leaf modules | `authenpam`, `datadumper`, `digestsha`, `findbin`, `iosocketip`, `mimebase32`, `mimebase64`, `netsubnet`, `posixstrptime`, `socket`, `termreadline`, `testharness`, `uuid` |
| Build helper libraries | `extjs`, `fonts-font-logos`, `markedjs`, `qrcodejs`, `perlmod`, `termproxy`, `unifont_hex`, `vncterm`, `cstream` |
| Build foundation packages | `proxmox-widget-toolkit`, `proxmox-i18n`, `pve-apiclient`, `proxmox-acme`, `proxmox-backup-qemu` |
| Validate build system | Confirm all RPMs install without conflicts on AlmaLinux |
| Validate dependency resolution | Run `resolve-deps.sh` against AlmaLinux repos, add missing deps to `dep-map.conf` or `dep-ignore.conf` |

**Deliverable**: ~30 RPMs installable on AlmaLinux, CI pipeline validated for batch builds.

### Phase 3: Core Infrastructure (Weeks 6–10)

**Goal**: Build Layers 2–5 — the core PVE services that everything else depends on.

| Task | Details |
|---|---|
| Build `pve-common` | Highest dependency count (25+ CPAN modules). Requires path patching: `/usr/bin/` → `/usr/bin/`, `/usr/share/zoneinfo` → AlmaLinux path, `/sbin/` path fixes. Reference `proxmox-nixos` `postFixup` for complete sed list. |
| Build `pve-rs` | Rust component. May need Cargo vendoring or network access during build. |
| Build `pve-access-control` | Depends on `pve-common`, `pve-apiclient`. |
| Build `pve-cluster` | Depends on `pve-access-control`, corosync, fuse, sqlite3, libqb. Critical package — must build `pmxcfs` (cluster filesystem) correctly. |
| Build `pve-http-server` | Depends on `pve-common`. |
| Build `pve-storage` | Depends on `pve-cluster`, `pve-rados2`, plus system tools (lvm2, nfs-utils, smartmontools, etc.). Path patching: `/sbin/zfs` → `/usr/sbin/zfs`, `/usr/bin/qemu` → path to `pve-qemu`. |
| Build `pve-firewall` | Depends on `pve-access-control`, `pve-cluster`, `pve-network`, iptables, ipset. |
| Build `pve-guest-common` | Depends on `pve-common`. |
| Build `pve-ha-manager` | Depends on `pve-cluster`, `pve-common`. |
| Build `pve-network` | Depends on `pve-common`. |

**Critical challenge**: `pve-common` has the most extensive path patching of any PVE package. The `postFixup` in `proxmox-nixos` shows the following substitutions must be applied:
- `/usr/share/zoneinfo` → AlmaLinux timezone path
- `/usr/bin/` → `/usr/bin/` (may be no-op on EL)
- `ovs-vsctl` → full path to `openvswitch`
- `ENV{'PATH'}` references must be removed or wrapped
- The `h2ph` tool (included in the `perl` package) must convert C syscall headers to Perl constants during the build process.

**Deliverable**: Core PVE services running on AlmaLinux (not yet integrated, but individually buildable and installable).

### Phase 4: Manager & Integration (Weeks 11–14)

**Goal**: Build `pve-manager` (the GUI), adapt systemd services, create unified target.

| Task | Details |
|---|---|
| Build `pve-qemu` | QEMU with Proxmox patches. Apply `debian/patches/series` (proxmox-nixos shows this is automated). Build with meson. Generate `recognized-CPUID-flags-x86_64` and `machine-versions-x86_64.json` (required by `pve-qemu-server`). |
| Build `pve-qemu-server` | Depends on `pve-common`, `pve-storage`, `pve-guest-common`, `pve-qemu`. |
| Build `pve-container` | Depends on `pve-common`, `pve-storage`, `pve-guest-common`, `lxc`. |
| Build `pve-manager` | The final package — highest dependency count. Path patching from `proxmox-nixos`: `/usr/share/javascript` → RPM path, `/usr/share/pve-docs` → RPM path, `/usr/share/pve-manager` → RPM path, `/usr/share/novnc-pve` → RPM path, `/usr/share/pve-xtermjs` → RPM path, `/usr/share/zoneinfo` → AlmaLinux path, `/usr/share/fonts-font-logos` → RPM path, `/usr/share/fonts-font-awesome` → RPM path, `/usr/share/pve-yew-mobile-gui` → RPM path, `/usr/share/pve-i18n` → RPM path, remove `API2::APT` references, remove `-T` taint flag from shebangs. |
| Adapt systemd service files | Convert PVE's init scripts and service files to proper systemd units. PVE on Debian uses a mix of systemd and custom init scripts. Key services: `pveproxy`, `pvedaemon`, `pvestatd`, `pve-cluster`, `pve-firewall`, `pve-ha-crm`, `pve-ha-lrm`, `pvenetcommit`, `pve-guests`. |
| Create unified systemd target | `pve.target` that `Wants=` all PVE services in the correct order. |
| Test web UI startup | Start `pveproxy`, verify port 8006 responds with the PVE login page. |

**Deliverable**: `pve-manager` RPM installed, `pveproxy` serving the PVE web UI on port 8006.

### Phase 5: Kernel & ZFS Integration (Weeks 15–16)

**Goal**: Validate stock kernel + KVM, install and test ZFS via GUI.

| Task | Details |
|---|---|
| Validate stock kernel + KVM | Boot AlmaLinux, verify KVM module loaded (`lsmod | grep kvm_intel`), create a test VM via PVE CLI. |
| Install ZFS DKMS | `dnf install zfs-dkms zfs`, verify module loads (`modprobe zfs`, `zpool status`). |
| Create ZFS pool via GUI | Use PVE web UI to create a ZFS pool on test disks. |
| Test VM creation on ZFS | Create a VM whose disk lives on the ZFS pool. Verify start/stop/snapshot. |
| Test LXC on ZFS | Create an LXC container on ZFS storage. Verify start/stop. |
| Snapshot testing | Test ZFS snapshot via PVE GUI (should call `zfs snapshot` under the hood). |

**Deliverable**: Working KVM VMs and LXC containers on ZFS storage, managed via PVE web UI.

### Phase 6: QA & Packaging (Weeks 17–20)

**Goal**: End-to-end testing, RPM repo generation, documentation.

| Task | Details |
|---|---|
| VM lifecycle testing | Create, start, stop, pause, resume, migrate, delete VMs of various OS types. |
| LXC container testing | Create, start, stop, snapshot, destroy containers. |
| Backup & restore testing | Test `vzdump` backup to local directory, restore from backup. |
| Firewall testing | Configure PVE firewall rules via GUI, verify iptables/nftables rules applied. |
| Network testing | Create Linux bridges, VLANs, OVS bridges via GUI. |
| RPM repo generation | `createrepo_c` to generate a signed YUM/DNF repository. Sign with GPG key. |
| Documentation | Write installation guide, known limitations, troubleshooting. |
| Release v0.1-alpha | Tag a release with known working version pins. |

**Deliverable**: Signed RPM repository, installation guide, alpha-quality release.

## 6. Risk Analysis

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| `pve-qemu` patches fail on EL kernel/toolchain | Medium | High | Use `proxmox-nixos` patch application strategy (read `debian/patches/series`, apply sequentially). QEMU builds are well-understood on EL; the Proxmox patches are small diffs. |
| Perl dependency hell (CPAN modules) | High | Medium | Vendor missing CPAN modules into sub-packages. `proxmox-nixos` already packages 13 custom Perl modules; CPAN modules available on EL via `perl-*` RPMs from EPEL and PowerTools. |
| ZFS DKMS break on kernel update | Medium | High | Pin kernel version in production. Test DKMS rebuild in CI before kernel updates. Use `akmods` alternative if DKMS proves fragile. |
| `pve-manager` Debian-isms (hardcoded paths) | High | High | Catalog all hardcoded paths from `proxmox-nixos` `postFixup` sed commands. The Nix expressions are the definitive reference for what needs patching. Create a comprehensive path-mapping table (Appendix B). |
| Maintenance burden per Proxmox release | High | High | Automate patch rebasing in CI. Pin versions in `packages.yml`. Test new PVE releases in CI before updating pins. |
| `pve-cluster` fuse/corosync integration | Medium | Medium | Corosync and fuse3 are available in EL10 repos. Test `pmxcfs` startup early in Phase 3. |
| `pve-manager` web UI asset compilation | Low | Medium | PVE uses ExtJS (already packaged as `extjs` in Nix) and biome for JS minification. Both available via npm. |
| SELinux conflicts | Medium | Medium | Set PVE services to permissive domain or create custom SELinux policy. AlmaLinux supports SELinux permissive mode for testing. |
| PVE API2::APT removal | Low | Low | `proxmox-nixos` already removes `API2::APT` references (Debian-specific package management). The sed command exists. |

## 7. Resource Requirements

### Skills

| Skill | Relevance |
|---|---|
| RPM packaging (specfiles, mock, createrepo) | Core — every PVE package must be packaged as RPM |
| Perl (pve-manager internals) | High — PVE is primarily Perl; path patching and dependency resolution require Perl understanding |
| C/build systems (meson, autotools for QEMU) | High — `pve-qemu` build requires meson; other components use Makefile-based builds |
| systemd service management | High — PVE services must be converted from Debian init scripts to systemd units |
| Docker/container builds | Medium — CI pipeline uses Docker containers |
| Shell/Bash scripting | Medium — build scripts and path patching |
| ZFS on Linux | Medium — DKMS module installation and testing |

### Infrastructure

| Resource | Purpose |
|---|---|
| GitHub Actions runners (or self-hosted) | CI pipeline — QEMU builds take 40+ minutes, need substantial runners |
| AlmaLinux 10 test VM(s) | Integration testing — minimum 8 GB RAM, 50 GB disk, nested virtualisation enabled |
| GPG key for RPM signing | Repository authenticity — generate a dedicated signing key |
| ZFS test disks | At least 2 spare block devices (or loop devices) for ZFS pool testing |

## 8. Success Criteria

- [ ] `pve-manager` starts and serves web UI on port 8006
- [ ] Can create and start a KVM VM via PVE CLI or GUI
- [ ] Can create and start an LXC container
- [ ] ZFS storage visible and manageable in GUI (pool creation, dataset creation)
- [ ] Snapshots work (ZFS snapshot via PVE GUI)
- [ ] Firewall rules configurable in GUI (iptables/nftables rules applied)
- [ ] Virtual networks configurable in GUI (Linux bridge, VLAN)
- [ ] VM lifecycle: start, stop, pause, resume, migrate (if multi-node)
- [ ] Backup and restore work (`vzdump` to local storage, restore)
- [ ] All packages install cleanly via `dnf` from the signed repository

## 9. Immediate Next Steps

1. **Fork/clone reference repositories** — Clone `proxmox-nixos` for reference (project `scripts/` already contains the packaging pipeline).
3. **Adapt reusable scripts** — `pkg-build-rpm.sh`, `pkg-extract.sh`, `cross-pkg-helpers.sh`, `resolve-deps.sh`, `dep-map.conf` — already present in project `scripts/`.
4. **Extend `dep-map.conf`** — Add Proxmox-specific Debian→RPM mappings for Perl modules, corosync, libqb, fuse3, etc.
5. **Write first `packages.yml`** — Start with Layer 0 Perl leaf packages (no dependencies, easy to validate).
6. **Build Docker image** — `almalinux:10` + dev tools + Perl 5.40 + meson + RPM build tools.
7. **Run first CI build** — Pick `uuid` or `digestsha` (simplest Perl module), validate end-to-end: fetch → extract → convert → RPM → install → test.

## 10. References

- **proxmox-nixos**: https://github.com/SaumonNet/proxmox-nixos — 1.3k stars, ~50 Nix expressions packaging all major PVE components
- **Proxmox source repositories**: https://git.proxmox.com/ — official Git server for all PVE packages
- **astralemu-packages** (historical upstream): `/home/gabriel/GIT/astralemu-packages/` — original local repo with multi-format packaging CI pipeline; the project's `scripts/` were forked from this repository
- **OpenZFS on Linux**: https://openzfs.github.io/openzfs-docs/ — ZFS DKMS module for EL distributions
- **AlmaLinux**: https://almalinux.org/ — RHEL-compatible distribution
- **EPEL**: https://docs.fedoraproject.org/en-US/epel/ — Extra Packages for Enterprise Linux
- **RPM packaging guide**: https://rpm-packaging-guide.github.io/

## Appendix A: Package Inventory (from proxmox-nixos)

Complete list of packages from `pkgs/default.nix`, with dependencies and purpose:

### Layer 0 — Perl Leaf Modules

| Package | Purpose | PVE Dependencies |
|---|---|---|
| `authenpam` | PAM authentication Perl module | None |
| `datadumper` | Data::Dumper Perl module | None |
| `digestsha` | Digest::SHA Perl module | None |
| `findbin` | FindBin Perl module | None |
| `iosocketip` | IO::Socket::IP Perl module | None |
| `mimebase32` | MIME::Base32 Perl module | None |
| `mimebase64` | MIME::Base64 Perl module | None |
| `netsubnet` | Net::Subnet Perl module | None |
| `posixstrptime` | POSIX::strptime Perl module | None |
| `socket` | IO::Socket Perl module | None |
| `termreadline` | Term::ReadLine Perl module | None |
| `testharness` | Test::Harness Perl module | None |
| `uuid` | UUID Perl module | None |

### Layer 1 — Helper Libraries

| Package | Purpose | PVE Dependencies |
|---|---|---|
| `extjs` | ExtJS JavaScript framework (web UI) | None |
| `fonts-font-logos` | Font Awesome + custom font icons | None |
| `markedjs` | Markdown parser (JavaScript) | None |
| `qrcodejs` | QR code generator (JavaScript) | None |
| `perlmod` | Perl module packaging helper | None |
| `termproxy` | Terminal proxy for web console | None |
| `unifont_hex` | GNU Unifont (hex format) | None |
| `vncterm` | VNC terminal emulator | None |
| `cstream` | Stream processing tool | None |

### Layer 2 — PVE Foundation

| Package | Purpose | PVE Dependencies |
|---|---|---|
| `proxmox-widget-toolkit` | JS/CSS widget toolkit for PVE UI | None |
| `proxmox-i18n` | Internationalisation framework | None |
| `pve-apiclient` | PVE API client library | None |
| `proxmox-acme` | ACME (Let's Encrypt) client | CPAN modules |
| `proxmox-backup-qemu` | Backup client for QEMU | None |
| `pve-docs` | PVE documentation generator | None |

### Layer 3 — Core Perl Libraries

| Package | Purpose | PVE Dependencies | Key System Dependencies |
|---|---|---|---|
| `pve-common` | Common Perl library for all PVE components | 25+ CPAN modules, `proxmox-backup-client` | `iproute2`, `openvswitch`, `pciutils`, `usbutils`, `systemd`, `tzdata` |
| `pve-rs` | Rust component (bindings) | `pve-common` | Cargo/Rust toolchain |

### Layer 4 — PVE Core Services

| Package | Purpose | PVE Dependencies | Key System Dependencies |
|---|---|---|---|
| `pve-access-control` | User/permission management | `pve-common`, `pve-apiclient` | PAM, LDAP |
| `pve-cluster` | Cluster filesystem (pmxcfs) | `pve-access-control`, `pve-apiclient`, `pve-rs` | `corosync`, `fuse3`, `sqlite3`, `libqb`, `rrdtool` |
| `pve-http-server` | HTTP server framework | `pve-common` | — |
| `pve-rados2` | Ceph RADOS bindings | `pve-common` | `librados` (optional) |

### Layer 5 — PVE Feature Modules

| Package | Purpose | PVE Dependencies | Key System Dependencies |
|---|---|---|---|
| `pve-storage` | Storage backend abstraction | `pve-cluster`, `pve-rados2` | `lvm2`, `nfs-utils`, `ceph`, `smartmontools`, `openiscsi`, `targetcli`, `samba` |
| `pve-firewall` | Host/guest firewall | `pve-access-control`, `pve-cluster`, `pve-network`, `pve-rs` | `iptables`, `ipset`, `libnetfilter_conntrack` |
| `pve-guest-common` | Guest (VM/CT) common code | `pve-common` | — |
| `pve-ha-manager` | High availability manager | `pve-cluster`, `pve-common` | `corosync` |
| `pve-network` | Network management (SDN) | `pve-common` | `openvswitch`, `iproute2` |

### Layer 6 — PVE Compute

| Package | Purpose | PVE Dependencies | Key System Dependencies |
|---|---|---|---|
| `pve-qemu` | QEMU with Proxmox patches | `proxmox-backup-qemu` | `meson`, full build toolchain, `libfdt`, `libcap-ng`, `libslirp`, etc. |
| `pve-qemu-server` | QEMU server management | `pve-common`, `pve-storage`, `pve-guest-common`, `pve-qemu` | — |
| `pve-container` | LXC container management | `pve-common`, `pve-storage`, `pve-guest-common` | `lxc`, `lxc-templates` |

### Layer 7 — PVE Manager (The GUI)

| Package | Purpose | PVE Dependencies | Key System Dependencies |
|---|---|---|---|
| `pve-manager` | Web UI + API server | ALL packages above | `graphviz`, `biome` (JS minifier), `sqlite3`, `corosync`, `openssh`, `ceph`, `lvm2` |
| `pve-novnc` | noVNC web client | None (static JS) | — |
| `pve-xtermjs` | xterm.js web terminal | None (static JS) | — |
| `pve-yew-mobile-gui` | Mobile web UI (Rust/WASM) | None | Rust/WASM toolchain |
| `pve-edk2-firmware` | UEFI firmware for VMs | None | — |

### Additional Packages

| Package | Purpose | PVE Dependencies |
|---|---|---|
| `linstor-api-py` | Linstor Python API | None |
| `linstor-client` | Linstor CLI client | None |
| `linstor-proxmox` | Linstor Proxmox plugin | `pve-storage` |
| `linstor-server` | Linstor server | Java runtime |
| `nixmoxer` | Nix-specific integration helper | None |
| `pve-update` | Update script helper | None |
| `mkRegistry` | NixOS module registration | None |

## Appendix B: Path Mapping (Debian → AlmaLinux)

Known hardcoded paths from `proxmox-nixos` `postFixup` sed commands, to be adapted for AlmaLinux:

### pve-common path substitutions

| Debian Path | AlmaLinux Target | Context |
|---|---|---|
| `/usr/share/zoneinfo` | `/usr/share/zoneinfo` | Same on EL — no change needed |
| `ovs-vsctl` | `/usr/bin/ovs-vsctl` | Open vSwitch CLI path |
| `ENV{'PATH'}` | Remove or wrap | PATH pollution prevention |
| `/usr/bin/`, `/usr/sbin/`, `/sbin/` | `/usr/bin/` | EL merges sbin into bin |

### pve-storage path substitutions

| Debian Path | AlmaLinux Target | Context |
|---|---|---|
| `/sbin/zfs` | `/usr/sbin/zfs` | ZFS binary path (or DKMS path) |
| `/sbin/zpool` | `/usr/sbin/zpool` | ZFS pool command |
| `/bin/lsblk` | `/usr/bin/lsblk` | Block device listing |
| `/bin/mkdir` | `/usr/bin/mkdir` | Directory creation |
| `/bin/mount` | `/usr/bin/mount` | Mount command |
| `/bin/umount` | `/usr/bin/umount` | Unmount command |
| `/sbin/blkid` | `/usr/sbin/blkid` | Block device identification |
| `/sbin/blockdev` | `/usr/sbin/blockdev` | Block device control |
| `/sbin/lv`, `/sbin/pv`, `/sbin/vg` | `/usr/sbin/lv`, `/usr/sbin/pv`, `/usr/sbin/vg` | LVM commands |
| `/sbin/mkfs` | `/usr/sbin/mkfs` | Filesystem creation |
| `/sbin/sgdisk` | `/usr/sbin/sgdisk` | GPT partitioning |
| `/sbin/showmount` | `/usr/sbin/showmount` | NFS mount listing |
| `/usr/bin/proxmox-backup-client` | `/usr/bin/proxmox-backup-client` | Backup client (our package) |
| `/usr/bin/qemu` | `/usr/bin/qemu-system-x86_64` | QEMU binary |
| `/usr/bin/rados` | `/usr/bin/rados` | Ceph RADOS CLI |
| `/usr/bin/rbd` | `/usr/bin/rbd` | Ceph RBD CLI |
| `/usr/bin/scp`, `/usr/bin/ssh` | `/usr/bin/scp`, `/usr/bin/ssh` | SSH commands (same path on EL) |
| `/usr/bin/smbclient` | `/usr/bin/smbclient` | Samba client |
| `/usr/bin/targetcli` | `/usr/bin/targetcli` | iSCSI target CLI |
| `/usr/bin/vma` | `/usr/bin/vma` | PVE backup format tool (our package) |
| `/usr/bin/zcat` | `/usr/bin/zcat` | Gzip decompression (same on EL) |
| `/usr/libexec/ceph` | `/usr/libexec/ceph` | Ceph exec path (same on EL) |
| `/usr/sbin/ceph` | `/usr/bin/ceph` | Ceph CLI (path differs on EL) |
| `/usr/sbin/gluster` | `/usr/sbin/gluster` | GlusterFS CLI |
| `/usr/sbin/smartctl` | `/usr/sbin/smartctl` | SMART monitoring |
| `/usr/share/perl5` | `/usr/share/perl5` | Perl library path |

### pve-manager path substitutions

| Debian Path | AlmaLinux Target | Context |
|---|---|---|
| `/usr/share/javascript` | `/usr/share/javascript` | JS assets (same on EL) |
| `/usr/share/pve-docs` | `/usr/share/pve-docs` | PVE documentation |
| `/usr/share/pve-manager` | `/usr/share/pve-manager` | PVE manager files |
| `/usr/share/novnc-pve` | `/usr/share/novnc-pve` | noVNC files (our package) |
| `/usr/share/pve-xtermjs` | `/usr/share/pve-xtermjs` | xterm.js files (our package) |
| `/usr/share/pve-yew-mobile-gui` | `/usr/share/pve-yew-mobile-gui` | Mobile GUI (our package) |
| `/usr/share/pve-i18n` | `/usr/share/pve-i18n` | Translations (our package) |
| `/usr/share/pve-yew-mobile-i18n` | `/usr/share/pve-yew-mobile-i18n` | Mobile translations |
| `/usr/share/fonts-font-logos` | `/usr/share/fonts-font-logos` | Custom font icons (our package) |
| `/usr/share/fonts-font-awesome` | `/usr/share/fonts-font-awesome` | Font Awesome (our package) |
| `/usr/share/bootstrap-html` | `/usr/share/bootstrap-html` | Bootstrap HTML |
| `/usr/share/perl5/$plug` | `/usr/share/perl5/$plug` | Perl module path (may differ) |
| `API2::APT` | Remove entirely | Debian-specific APT management |
| `-T` flag | Remove from shebangs | Perl taint mode removal (for systemd) |

### pve-cluster path substitutions

| Debian Path | AlmaLinux Target | Context |
|---|---|---|
| `/usr` prefix in Makefiles | Remove `/usr` prefix | NixOS uses no `/usr`; on EL, `/usr` is standard |

### General pattern

Most path substitutions fall into these categories:
1. **sbin → bin merge**: On EL10, `/sbin` and `/usr/sbin` are symlinks to `/usr/bin`, continuing the merge started in EL9. Path references like `/sbin/zfs` should become `/usr/sbin/zfs` (or just rely on PATH). **Note**: on AlmaLinux 10, `/sbin` and `/usr/sbin` are symlinks pointing to `/usr/bin/`, as they were on AlmaLinux 9. This means references to `/usr/sbin/xxx` work via symlink resolution, but the actual binary resides in `/usr/bin/`. When patching PVE source code, prefer `/usr/bin/` as the canonical path, or rely on `$PATH` lookup rather than hardcoding `/usr/sbin/`.
2. **Package install paths**: `/usr/share/perl5` may need adjustment depending on how RPM Perl modules are installed.
3. **Debian-specific removal**: `API2::APT` and APT-related code must be stripped.
4. **Wrapper PATH injection**: Instead of sed-replacing every binary path, the project's own `scripts/` approach of using `--prefix PATH` in RPM scriptlets (or `wrapProgram` equivalent, as demonstrated in `proxmox-nixos`) is cleaner.