#!/bin/sh

DISK_DEVICE=/dev/nvme0n1p1
DISK_IMAGE=/home/vajain21/mglru-benchmark/mongodb.qcow2
systemctl stop mongodb.service
umount /data
e2image -I ${DISK_DEVICE} ${DISK_IMAGE}
mount /data
systemctl start mongodb.service
sleep 1
systemctl status mongodb.service


