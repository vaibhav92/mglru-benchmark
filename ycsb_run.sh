#!/bin/bash
#PATH=$PATH:/home/vajain21/YCSB/bin
BENCH_CONF=$(dirname $0)/../data/bench.conf
echo Reading configuration from ${BENCH_CONF}
source ${BENCH_CONF}
export ${YCSB_HOME}

#initial setup
echo "Stopping Mongodb and  Unmounting Data disk"
systemctl daemon-reload
systemctl stop mongodb
umount ${DISK_DEVICE}

# setup the results DIR
mkdir -p ${RESULTS_DIR}

#find the last run index and distribution
LAST_RUN=$(ls -1 ${RESULTS_DIR} | sort -nr | head -n1)
LAST_DISTRIBUTION=zipfian
LAST_KERNEL=""

if [ -n "${LAST_RUN}" ]; then
    #check for last distribution used
    if [ -f ${RESULTS_DIR}/${LAST_RUN}/distribution ]; then
	LAST_DISTRIBUTION=$(cat ${RESULTS_DIR}/${LAST_RUN}/distribution)
    fi
    if [ -f ${RESULTS_DIR}/${LAST_RUN}/boot.kernel ]; then
	LAST_KERNEL=$(cat ${RESULTS_DIR}/${LAST_RUN}/boot.kernel)
    fi
else
    LAST_RUN=0
fi

CURRENT_KERNEL=$(uname -r)
CURRENT_RUN=$((${LAST_RUN} + 1))
DISTRIBUTION=uniform
#find the next distribution to try
if [ "${LAST_DISTRIBUTION}" == "zipfian" ]; then
    DISTRIBUTION=uniform
elif [ "${LAST_DISTRIBUTION}" == "uniform" ]; then
    DISTRIBUTION=exponential
elif [ "${LAST_DISTRIBUTION}" == "exponential" ]; then
    DISTRIBUTION=zipfian
else
    echo "Unknown Last Distribution ${LAST_DISTRIBUTION}"
    DISTRIBUTION=uniform
fi

echo "Last Distribution " ${LAST_DISTRIBUTION}
echo "Curr Distribution " ${DISTRIBUTION}
echo "Last Kernel " ${LAST_KERNEL}
echo "Curr Kernel " ${CURRENT_KERNEL}


#setup the results dir
mkdir -p ${RESULTS_DIR}/${CURRENT_RUN}
RESULTS_DIR=$(readlink -f ${RESULTS_DIR}/${CURRENT_RUN})
echo "Dumping results to ${RESULTS_DIR}"

#generate configuration for mongodb
echo "Generating Mongodb Configuration"
cp -f mongod.conf ${RESULTS_DIR}
ln -sf -t /etc ${RESULTS_DIR}/mongod.conf

echo "Restoring disk image"
#e2image -I ${DISK_DEVICE} ${DISK_IMAGE}
qemu-img convert -p -O raw -f qcow2 ${DISK_IMAGE} ${DISK_DEVICE}

echo "Remounting disk"
mount ${DISK_DEVICE} ${MOUNT_POINT}

echo "Restarting Mongodb"
systemctl restart mongodb.slice
systemctl start mongodb.service
sleep 4
echo -n "Checking if MongoDB is alive.."
systemctl is-active mongodb.service || exit 1

#check the mongodb url to use
MONGO_SOCK=$(ls -1 /run/mongodb/*.sock | head -n1)
if [ -z "${MONGO_SOCK}" ]; then
    echo "Unable to find Mongodb Unix Socket"
    exit 1
fi

MONGO_URL=$(echo ${MONGO_SOCK} | sed 's|/|%2F|g')
echo "Using Mongodb URL ${MONGO_URL}"

WORKLOAD="python2 ./bin/ycsb run mongodb -s -threads 64 \
    -p mongodb.url=mongodb://${MONGO_URL} \
    -p workload=site.ycsb.workloads.CoreWorkload \
    -p recordcount=${YCSB_RECORD_COUNT} -p operationcount=${YCSB_OPERATION_COUNT} \
    -p readproportion=0.8 -p updateproportion=0.2 \
    -p requestdistribution=${DISTRIBUTION}"

echo "${DISTRIBUTION}" > ${RESULTS_DIR}/distribution
echo "${CURRENT_KERNEL}" > ${RESULTS_DIR}/boot.kernel
echo $(cat /proc/cmdline) >> ${RESULTS_DIR}/boot.cmdline
echo ${WORKLOAD} > ${RESULTS_DIR}/workload

echo "Collecting initial data"
date > ${RESULTS_DIR}/timestamp.intial
cp /proc/vmstat ${RESULTS_DIR}/vmstat.initial

# run the workload
echo Staring workload ${WORKLOAD}
pushd . > /dev/null
cd ${YCSB_HOME}
${WORKLOAD} 2>&1 | tee "${RESULTS_DIR}/ycsb.log"
[ "$?" -ne "0" ] && exit 1
popd  > /dev/null

#collect other metrics
echo "Collecting Metrices"
cp /sys/fs/cgroup/mongodb.slice/memory.* ${RESULTS_DIR}
cp /proc/vmstat ${RESULTS_DIR}/vmstat.final
date > ${RESULTS_DIR}/timestamp.final

#cleanup
echo "Cleanup/Stopping Services"
systemctl stop mongodb
umount ${DISK_DEVICE}
systemctl stop mongodb.slice

echo "Picking up next kernel to boot"

#switch kernel needed
if [ "${DISTRIBUTION}" == "zipfian" ]; then
    if [[ "${CURRENT_KERNEL}" =~ 'non-mglru' ]]; then
	NEXT_BOOT_TYPE="mglru"
    else
	NEXT_BOOT_TYPE="non-mglru"
    fi
else
    if [[ "${CURRENT_KERNEL}" =~ 'non-mglru' ]]; then
	NEXT_BOOT_TYPE="non-mglru"
    else
	NEXT_BOOT_TYPE="mglru"
    fi
fi

echo Next boot of Kernel=vmlinux-${NEXT_BOOT_TYPE} and Initrd=initrd-${NEXT_BOOT_TYPE} | tee ${RESULTS_DIR}/next-kernel
#load the kexec kernel and initrd
kexec -sl --initrd ${DATA_DIR}/initrd-${NEXT_BOOT_TYPE} ${DATA_DIR}/vmlinux-${NEXT_BOOT_TYPE} --append="${KERNEL_BOOT_ARGS}" || exit 1


echo "Sleeping for 30 seconds before next reboot"
sync
sleep 30

#boot into next kernel
kexec -e

#never reached
exit 1
