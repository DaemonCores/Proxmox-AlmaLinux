# Proxmox Alma Packages

> Proxmox VE ported to AlmaLinux as an atomic bootc image.

Proxmox AlmaLinux ports the Proxmox VE (PVE) userspace to RPM format on top of the
stock AlmaLinux EL kernel with OpenZFS DKMS — bypassing the `pve-kernel`
entirely. The result is a bootc-compatible container image that can be
installed via Anaconda kickstart or updated atomically through the bootc
transport.

## Architecture

| Layer | Component | Source |
|--------|-----------|--------|
| Kernel | Stock AlmaLinux EL10 kernel | AlmaLinux repos |
| Storage | OpenZFS via DKMS | OpenZFS project |
| Userspace | PVE packages rebuilt as RPMs | git.proxmox.com |
| Runtime | bootc-compatible container image | This repo (`Dockerfile`) |
| Installer | Anaconda kickstart pulling from GHCR | `iso.ks` |

The porting strategy is validated by [proxmox-nixos](https://github.com/SaumonNet/proxmox-nixos),
which proves that PVE core is portable without `pve-kernel`.

## Repository Structure

```
.
├── packages.yml              # PVE package definitions (id, layer, deps, build time)
├── scripts/                  # Build & packaging helpers
│   ├── cross-pkg-helpers.sh  # Cross-distro lib-path relocation
│   ├── dep-map.conf          # Dependency mapping configuration
│   ├── pkg-build-rpm.sh      # RPM build driver
│   ├── pkg-extract.sh        # Source extraction from Proxmox git
│   └── resolve-deps.sh       # Recursive dependency resolution
├── .github/workflows/        # CI/CD pipelines
│   ├── bootc-build.yml       # Build & push container image to GHCR
│   └── iso.yml               # Generate bootable ISO with kickstart
├── Dockerfile                # AlmaLinux 10 build + runtime image
├── iso.ks                    # Anaconda kickstart (pulls bootc from GHCR)
├── docs/
│   └── PROXMOX_ALMA_PORTING_PLAN.md  # Detailed porting plan & analysis
└── src/                      # Runtime overlay (currently empty)
```

## Building

### Docker (local)

```bash
docker build -t proxmox-almalinux .
```

### GitHub Actions (CI)

1. **Container image** — triggered on push to `Dockerfile` / `.dockerignore` / `src/`:
   - Builds the bootc image and pushes to `ghcr.io/daemoncores/proxmox-almalinux`
   - Workflow: `.github/workflows/bootc-build.yml`

2. **ISO** — manual dispatch only:
   - Downloads AlmaLinux boot ISO, injects kickstart, uploads release artifact
   - Workflow: `.github/workflows/iso.yml`

## Package Build Pipeline

Packages are defined in `packages.yml` with a layered dependency graph
(Layer 0–7). The CI iterates over entries, resolves dependencies from
`depends_on` fields, and schedules build waves automatically.

To add a new package:
1. Add an entry to `packages.yml` with a unique `id`
2. Create `packages/<id>/build.sh` with the build logic
3. Commit and push — CI builds it

## Reference Projects

| Project | Role |
|---------|------|
| [proxmox-nixos](https://github.com/SaumonNet/proxmox-nixos) | Complete PVE package graph and build orchestration reference (50+ Nix expressions) |
| `Proxmox AlmaLinux` | Reusable CI/CD plumbing for RPM package conversion (30–40% of infrastructure scripts) |

## Status

**Phase 1 — Bootstrap** (in progress)

The porting plan, package definitions, build tooling, and CI pipelines are
in place. Individual PVE package builds are being validated layer by layer.

## License

LGPL-2.1 — see [LICENSE](LICENSE).