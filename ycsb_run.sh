#!/bin/bash
#PATH=$PATH:/home/vajain21/YCSB/bin
DISK_DEVICE=/dev/nvme0n1p1
DISK_RESTORE_DEVICE=/dev/nvme0n1p2
MOUNT_POINT=/data
DISK_IMAGE=/home/vajain21/mglru-benchmark/mongodb.qcow2
export YCSB_HOME=/home/vajain21/YCSB

RESULTS_DIR=results
DISTRIBUTION=uniform

systemctl stop mongodb
umount ${DISK_DEVICE}

echo "Restoring disk image"
#e2image -I ${DISK_DEVICE} ${DISK_IMAGE}
#dd if=${DISK_RESTORE_DEVICE} of=${DISK_DEVICE} status=progress bs=64K
qemu-img convert -p -O raw -f qcow2 ${DISK_IMAGE} ${DISK_DEVICE}

mount ${DISK_DEVICE} ${MOUNT_POINT}
systemctl start mongodb.service
sleep 1
systemctl status mongodb.service || exit 1

MONGO_URL=%2Frun%2Fmongodb%2F$(basename $(ls -1 /run/mongodb/*.sock | head -n1))
echo ${MONGO_URL}

# setup the results DIR
RESULTS_DIR=$RESULTS_DIR/$(uname -r)

#check for requested distribution
[ ! -d "${RESULTS_DIR}/zipfian" ] && DISTRIBUTION=zipfian
[ ! -d "${RESULTS_DIR}/exponential" ] && DISTRIBUTION=exponential
[ ! -d "${RESULTS_DIR}/uniform" ] && DISTRIBUTION=uniform

mkdir -p ${RESULTS_DIR}/${DISTRIBUTION}
RESULTS_DIR=$(readlink -f ${RESULTS_DIR}/${DISTRIBUTION})
echo "Dumping results to ${RESULTS_DIR}"

pushd .
cd ${YCSB_HOME}
# run the workload
python2 ./bin/ycsb -cp $(find scylla/target/dependency/ -name '*.jar' | tr '\n' ':') run mongodb -s -threads 64 \
    -p mongodb.url=mongodb://${MONGO_URL} \
    -p workload=site.ycsb.workloads.CoreWorkload \
    -p recordcount=80000000 -p operationcount=80000000 \
    -p readproportion=0.8 -p updateproportion=0.2 \
    -p requestdistribution=${DISTRIBUTION} 2>&1 | tee ${RESULTS_DIR}/ycsb.log
popd
