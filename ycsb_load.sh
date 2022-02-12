#!/bin/bash

BENCH_CONF=$(dirname $0)/../data/bench.conf
echo Reading configuration from ${BENCH_CONF}
source ${BENCH_CONF}
export ${YCSB_HOME}

rm -f ${DISK_IMAGE}
systemctl stop mongodb
umount ${DISK_DEVICE}
mkfs.ext4 -F ${DISK_DEVICE}
mount ${DISK_DEVICE} ${MOUNT_POINT}
mkdir ${MOUNT_POINT}/db
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
    -p recordcount=${YCSB_RECORD_COUNT}
popd

echo "Stopping Mongodb Service"
systemctl stop mongodb.service
sync
umount ${MOUNT_POINT}
echo "Creating disk image to ${DISK_IMAGE}"
e2image -Qa ${DISK_DEVICE} ${DISK_IMAGE}
