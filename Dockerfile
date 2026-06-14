# syntax=docker/dockerfile:1.7
# AlmaLinux 10 BUILD image for Proxmox VE
# Hybrid build+deploy image: provides full build toolchain and PVE runtime dependencies
FROM almalinux:10

# --- EPEL repository ---
RUN dnf install -y epel-release \
    && dnf clean all

# --- Base tools ---
RUN dnf install -y \
        bash \
        curl \
        wget \
        git \
        tar \
        gzip \
        xz \
        patch \
        diffutils \
    && dnf clean all

# --- Build tools ---
RUN dnf install -y \
        gcc \
        gcc-c++ \
        make \
        cmake \
        meson \
        ninja-build \
        automake \
        autoconf \
        libtool \
        rpm-build \
        rpmlint \
    && dnf clean all

# --- Perl 5.40 ---
RUN dnf install -y \
        perl \
        perl-devel \
        perl-ExtUtils-Embed \
        perl-CPAN \
    && dnf clean all

# --- Proxmox VE system dependencies ---
RUN dnf install -y \
        corosync-devel \
        libqb-devel \
        fuse3-devel \
        openvswitch \
        lvm2 \
        device-mapper-multipath \
        iscsi-initiator-utils \
        targetcli \
        nfs-utils \
        rpcbind \
        smartmontools \
        qemu-kvm \
        qemu-img \
        libvirt-client \
        bridge-utils \
        dnsmasq \
        iproute \
        iptables \
        ipset \
        ebtables \
        nftables \
    && dnf clean all

# --- Development libraries ---
RUN dnf install -y \
        openssl-devel \
        libxml2-devel \
        libuuid-devel \
        libblkid-devel \
        pango-devel \
        glib2-devel \
        json-c-devel \
        libtirpc-devel \
        sqlite-devel \
        rrdtool-devel \
        boost-devel \
        jansson-devel \
    && dnf clean all

# --- Rust toolchain (for pve-rs) ---
RUN dnf install -y \
        rust \
        cargo \
    && dnf clean all

# --- Additional tools ---
RUN dnf install -y \
        createrepo_c \
        gnupg2 \
        which \
    && dnf clean all

# Hybrid build+deploy image: this label marks it as a bootc-compatible image
# while the primary purpose is to serve as a build environment for PVE packages
LABEL containers.bootc="1"