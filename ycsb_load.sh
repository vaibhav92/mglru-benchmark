#!/bin/bash

BENCH_HOME=$(dirname $0)
BENCH_CONF=${BENCH_HOME}/../data/bench.conf
echo Reading configuration from ${BENCH_CONF}
source ${BENCH_CONF}
source ${BENCH_HOME}/common.sh


#reset and restart the currently runing instance of mongodb
reset_mongodb;

MONGO_URL=$(get_mongodb_url)
echo "Populating Mongodb instance ${MONGO_URL}"

# load objects
python2 ${YCSB_HOME}/bin/ycsb load mongodb -s -threads 1 \
    -p mongodb.url=${MONGO_URL} \
    -p workload=site.ycsb.workloads.CoreWorkload \
    -p recordcount=${YCSB_RECORD_COUNT} || exit 1

stop_mongodb
echo "Creating disk image to ${DISK_IMAGE}"
rm -f ${DISK_IMAGE}
e2image -Qa ${MONGODB_DISK} ${DISK_IMAGE}
