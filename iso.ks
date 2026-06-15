# personal-server net-install kickstart
# Anaconda pulls the bootc image from GHCR at install time.

network --hostname=proxmox-almalinux

# Pull the bootc image from the registry
ostreecontainer --url=ghcr.io/daemoncores/proxmox-almalinux:latest --no-signature-verification

# Reboot after install
reboot
