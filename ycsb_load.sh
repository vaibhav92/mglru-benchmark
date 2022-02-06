#!/bin/bash
#PATH=$PATH:/home/vajain21/YCSB/bin
DISK_DEVICE=/dev/pmem0s
MOUNT_POINT=/data
DISK_IMAGE=/home/vajain21/mglru/data/mongodb.qcow2
export YCSB_HOME=/home/vajain21/mglru/YCSB

rm -f ${DISK_IMAGE}
systemctl stop mongodb
umount ${DISK_DEVICE}
mkfs.ext4 -F ${DISK_DEVICE}
mount ${DISK_DEVICE} ${MOUNT_POINT}
mkdir ${MOUNT_POINT}/db
chown mongodb:mongodb ${MOUNT_POINT}/db
systemctl start mongodb.service
sleep 1
systemctl is-active mongodb.service || exit 1

MONGO_URL='%2Frun%2Fmongodb%2F'$(basename $(ls -1 /run/mongodb/*.sock | head -n1))
echo ${MONGO_URL}

pushd .
cd ${YCSB_HOME}
# load objects
python2 ./bin/ycsb load mongodb -s -threads 1 \
    -p mongodb.url=mongodb://${MONGO_URL} \
    -p workload=site.ycsb.workloads.CoreWorkload \
    -p recordcount=80000000
popd

echo "Stopping Mongodb Service"
systemctl stop mongodb.service
sync
umount ${MOUNT_POINT}
echo "Creating disk image to ${DISK_IMAGE}"
e2image -Qa ${DISK_DEVICE} ${DISK_IMAGE}
