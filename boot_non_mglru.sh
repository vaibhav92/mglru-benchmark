#!/bin/sh
#BOOT_TYPE="mglru+"
BOOT_TYPE="non-mglru"
KERNEL_ARGS="systemd.unified_cgroup_hierarchy=1 root=UUID=b6b1ae58-7257-4b52-bd60-baedc42f39e4 transparent_hugepage=never"
kexec -s --initrd ../data/initrd-${BOOT_TYPE} ../data/vmlinux-${BOOT_TYPE} --append="$(cat /proc/cmdline)"
kexec -e
