#!/bin/bash

BENCH_HOME=$(dirname $0)
BENCH_CONF=${BENCH_HOME}/../data/bench.conf
echo Reading configuration from ${BENCH_CONF}
source ${BENCH_CONF}
source ${BENCH_HOME}/common.sh


#check if we are booting into a mglru/nonmglru kernel
check_and_boot_to_non_mglru_if_needed;

#initial setup
stop_mongodb

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

echo "Restoring disk image"
#e2image -I ${MONGODB_DISK} ${DISK_IMAGE}
${QEMU_IMG} convert -p -O raw -f qcow2 ${DISK_IMAGE} ${MONGODB_DISK}

#generate and update configuration for mongodb
echo "Generating Mongodb Configuration"
cp -f ${DATA_DIR}/mongod.conf ${RESULTS_DIR}
cp ${RESULTS_DIR}/mongod.conf /etc

start_mongodb;

MONGO_URL=$(get_mongodb_url)
echo "Using Mongodb URL ${MONGO_URL}"

WORKLOAD_DIR="${YCSB_HOME}"
WORKLOAD="python2 ${YCSB_HOME}/bin/ycsb run mongodb -s -threads 64 \
    -p mongodb.url${MONGO_URL} \
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
cp /proc/meminfo ${RESULTS_DIR}/meminfo
cp /proc/cpuinfo ${RESULTS_DIR}/cpuinfo

# run the workload
echo Staring workload ${WORKLOAD} at ${WORKLOAD_DIR}
pushd .
cd ${WORKLOAD_DIR}
${WORKLOAD} 2>&1 | tee "${RESULTS_DIR}/ycsb.log"
if [ "$?" -ne "0" ]; then
    popd
    exit 1
fi
popd
#collect other metrics
echo "Collecting Metrices"
cp /sys/fs/cgroup/mongodb.slice/memory.* ${RESULTS_DIR}
cp /proc/vmstat ${RESULTS_DIR}/vmstat.final
date > ${RESULTS_DIR}/timestamp.final

#cleanup
stop_mongodb

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

boot_next_kernel ${NEXT_BOOT_TYPE}

#never reached
exit 1
