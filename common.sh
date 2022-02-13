#!/bin/bash

#COMMON procedures for the bench

################################################################################
# Boot into a MGLRU/NONGLRU kernel based on $1 arg
################################################################################
boot_next_kernel() {
    NEXT_BOOT_TYPE=$1
    echo Next boot of Kernel=vmlinux-${NEXT_BOOT_TYPE} and Initrd=initrd-${NEXT_BOOT_TYPE} | tee ${RESULTS_DIR}/next-kernel
    
    echo "Sleeping for 30 seconds before next reboot"
    sleep 30 || exit 1
    
    #load the kexec kernel and initrd
    kexec -sl --initrd ${DATA_DIR}/initrd-${NEXT_BOOT_TYPE} ${DATA_DIR}/vmlinux-${NEXT_BOOT_TYPE} --append="${KERNEL_BOOT_ARGS}" || exit 1
    sync
    #boot into next kernel
    kexec -e
}

stop_mongodb() {
    echo "Stopping Mongodb and Unmounting Data disk"
    systemctl stop mongodb
    sync
    umount ${MONGODB_DISK}
}

check_and_boot_to_non_mglru_if_needed() {
    ## Check if we are booted into a mglru or non-mglru kernel
    CURRENT_KERNEL=$(uname -r)
    if [[ ! "${CURRENT_KERNEL}" =~ '-mglru' ]]; then
	boot_next_kernel "non-mglru"
    fi
}

start_mongodb() {
    echo "Remounting disk"
    mount ${MONGODB_DISK} ${MONGO_DATA_DIR} || exit 1
    mkdir ${MONGO_DATA_DIR} 2> /dev/null
    echo "Starting Mongodb .."
    systemctl restart mongodb.slice
    systemctl start mongodb.service || exit 1
    echo -n "Checking if MongoDB is alive.."
    sleep 5
    systemctl is-active mongodb.service
    if [ "$?" -ne "0" ]; then
	>&2 echo "Unable to start mongodb service"
	exit 1
    fi
}

reset_mongodb() {
    echo "Resetting Mongodb"
    stop_mongodb;
    echo "Prepping disk ${MONGODB_DISK}"
    mkfs.ext4 -F ${MONGODB_DISK}
    start_mongodb;
}

get_mongodb_url() {
    MONGO_SOCK=$(ls -1 /run/mongodb/*.sock | head -n1)
    if [ -z "${MONGO_SOCK}" ]; then
	>&2 echo "Unable to find Mongodb Unix Socket"
	exit 1
    fi
    MONGO_SOCK=$(echo ${MONGO_SOCK} | sed 's|/|%2F|g' )
    echo "mongodb://${MONGO_SOCK}"
}
