#!/bin/sh

KERNEL_ARGS="systemd.unified_cgroup_hierarchy=1 root=UUID=b6b1ae58-7257-4b52-bd60-baedc42f39e4 transparent_hugepage=never"
kexec -s --initrd ../linux/initrd-mglru.img ../linux/vmlinux-mglru --append="$KERNEL_ARGS $EXTRA_ARGS"
kexec -e
