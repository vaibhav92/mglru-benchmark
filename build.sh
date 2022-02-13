#!/bin/bash

################################################################################
## Configuration Section
################################################################################
KERNEL_SOURCE_MGLRU=https://linux-mm.googlesource.com/page-reclaim
KERNEL_SOURCE_REF_MGLRU=refs/changes/49/1549/1
KERNEL_SOURCE_NON_MGLRU=https://github.com/torvalds/linux/
KERNEL_SOURCE_REF_NON_MGLRU=v5.16
KERNEL_BOOT_ARGS="transparent_hugepage=never systemd.unified_cgroup_hierarchy=1"
KERNEL_CONFIG_MGLRU="config-mglru"
KERNEL_CONFIG_NON_MGLRU="config-non-mglru"

QEMU_SOURCE="https://git.qemu.org/git/qemu.git"
QEMU_SOURCE_REF="v6.1.1"

MONGODB_SOURCE=https://github.com/mongodb/mongo.git
MONGODB_SOURCE_REF="r5.0.6"

YCSB_SOURCE=https://github.com/vaibhav92/YCSB.git
YCSB_SOURCE_REF=mongodb-domain-sockets

MGLRU_BENCH_SOURCE=https://github.com/vaibhav92/mglru-benchmark.git
MGLRU_BENCH_SOURCE_REF="auto_build"

################################################################################
# Validation Section
################################################################################
if [[ -z "${MONGODB_DISK}"  || ! -b "${MONGODB_DISK}" ]]; then
    echo "Need a block device for var MONGODB_DISK not ${MONGODB_DISK}"
    exit 1
fi

#check the disk size
DISK_SIZE=$(lsblk  ${MONGODB_DISK} -bno SIZE)
MIN_DISK_SIZE=$((1024*1024*1024*100))
if [ "${DISK_SIZE}" -lt "${MIN_DISK_SIZE}" ]; then
    echo "Need disk size atleast ${MIN_DISK_SIZE} bytes"
    exit 1
fi
echo "Using disk ${MONGODB_DISK} of size ${DISK_SIZE} bytes"

#check the memory size
MEM_SIZE_KB=$(grep 'MemTotal:' /proc/meminfo| grep -oe '[[:digit:]]*')
MEM_SIZE=$((${MEM_SIZE_KB} / 1024 / 1024)) # Convert to GiB
echo "Running on system with ${MEM_SIZE} GiB memory"

#create needed dirs
pushd .
mkdir mglru 2>/dev/null
cd mglru
mkdir -p linux mongo ycsb data bench results data/mongodb qemu 2> /dev/null

DATA_DIR=$(readlink -f data)
RESULTS_DIR=$(readlink -f results)
DISK_IMAGE=${DATA_DIR}/mongodb.qcow2
BENCH_DIR=$(readlink -f bench)

################################################################################
# Pull  Bench Dependencies
################################################################################
#install dependencies for RHEL 8.4
echo "Installing dependencies...."
dnf install -y git gcc make flex bison openssl-devel python2 python36 python36-devel\
    maven libcurl-devel gcc-c++ elfutils-libelf-devel tar e2fsprogs \
    util-linux numactl dwarves meson ninja-build glib2-devel bzip2 pixman-devel
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi

echo "Downloading MGLRU Bench from "${MGLRU_BENCH_SOURCE} Ref:${MGLRU_BENCH_SOURCE_REF}
[ -d 'bench/.git' ] || git -C bench init
git -C bench fetch ${MGLRU_BENCH_SOURCE} ${MGLRU_BENCH_SOURCE_REF}
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
git -C bench checkout FETCH_HEAD
cp -vf "${BENCH_DIR}/mglru-benchmark.service" "${DATA_DIR}"
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi

#clone linux kernel and mglru tree
[ -d 'linux/.git' ] || git -C linux init
echo Downloading MGLRU Tree from ${KERNEL_SOURCE_MGLRU} ${KERNEL_SOURCE_REF_MGLRU}
git -C linux fetch ${KERNEL_SOURCE_MGLRU} ${KERNEL_SOURCE_REF_MGLRU}
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
echo Downloading MGLRU Tree from ${KERNEL_SOURCE_NON_MGLRU} ${KERNEL_SOURCE_REF_NON_MGLRU}
git -C linux fetch ${KERNEL_SOURCE_NON_MGLRU} ${KERNEL_SOURCE_REF_NON_MGLRU}
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi

#clone mongodb community server
[ -d 'mongo/.git' ] || git -C mongo init
echo Downloading Mongodb Community Server from ${MONGODB_SOURCE} Ref:${MONGODB_SOURCE_REF}
git -C mongo fetch ${MONGODB_SOURCE} ${MONGODB_SOURCE_REF}
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
git -C mongo checkout FETCH_HEAD

#clone YCSB repo
echo Downloading YCSB source from ${YCSB_SOURCE}  Ref:${YCSB_SOURCE_REF}
[ -d 'ycsb/.git' ] || git -C ycsb init
git -C ycsb fetch ${YCSB_SOURCE} ${YCSB_SOURCE_REF}
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
git -C ycsb checkout FETCH_HEAD

#clone qemu repo
echo Downloading qemu source from ${QEMU_SOURCE}  Ref:${QEMU_SOURCE_REF}
[ -d 'qemu/.git' ] || git -C qemu init
git -C qemu fetch ${QEMU_SOURCE} ${QEMU_SOURCE_REF}
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
git -C qemu checkout FETCH_HEAD

################################################################################
# Build + Install Bench Dependencies
################################################################################
#build qemu
echo "Building Qemu..ver:${QEMU_SOURCE_REF}"
cd qemu
if [ ! -x "./build/qemu-img" ]; then
    mkdir build; cd build;
    ../configure --disable-user --disable-system --enable-tools \
		 --disable-capstone --disable-guest-agent --enable-debug \
	&& ninja
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    #check if qemu-img was generated
    if [ ! -x "./qemu-img" ]; then popd ;exit 1;fi
    cd ..
fi
cd ..
QEMU_IMG=$(readlink -f ./qemu/build/qemu-img)

#build and install mongodb
MONGO_VERSION=$(echo ${MONGODB_SOURCE_REF} | sed 's/^r//')
echo "Building Mongodb..ver:${MONGO_VERSION}"
cd mongo
python3 -m pip install -r etc/pip/compile-requirements.txt
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi

python3 buildscripts/scons.py DESTDIR=/opt/mongo MONGO_VERSION=${MONGO_VERSION} install-core
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
cd ..

#build YCSB repo
echo "Building YCSB.."
cd ycsb
mvn -pl site.ycsb:mongodb-binding -am clean package
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
export YCSB_HOME=$(readlink -f .)
cd ..

cd linux
if [ ! -f "${DATA_DIR}/vmlinux-non-mglru" ]; then
    #build the non-mglru  kernel
    echo "Building NON-MGLRU Kernel"
    git fetch ${KERNEL_SOURCE_NON_MGLRU} ${KERNEL_SOURCE_REF_NON_MGLRU} && git checkout FETCH_HEAD
    echo "Copying kernel config"
    cp -vf ${BENCH_DIR}/${KERNEL_CONFIG_NON_MGLRU} .config
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    make olddefconfig && make -j 32 vmlinux modules && make modules_install
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    cp -f vmlinux ${DATA_DIR}/vmlinux-non-mglru
    dracut --kver $(make kernelrelease)  --force ${DATA_DIR}/initrd-non-mglru
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    cp -f .config ${DATA_DIR}/config-non-mglru
fi


#build the mglru kernel
if [ ! -f "${DATA_DIR}/vmlinux-mglru" ]; then
    echo "Building MGLRU Kernel"
    git fetch ${KERNEL_SOURCE_MGLRU} ${KERNEL_SOURCE_REF_MGLRU} && git checkout FETCH_HEAD
    echo "Copying kernel config"
    cp -vf ${BENCH_DIR}/${KERNEL_CONFIG_MGLRU} .config
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    make olddefconfig && make -j 32 vmlinux modules && make modules_install
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    cp -f vmlinux ${DATA_DIR}/vmlinux-mglru
    dracut --kver $(make kernelrelease)  --force ${DATA_DIR}/initrd-mglru
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    cp -f .config ${DATA_DIR}/config-mglru
fi
make distclean 2> /dev/null
cd ..

#retore the original directory
popd

################################################################################
# Bench Configuration
################################################################################
#get common functions
source ${BENCH_DIR}/common.sh

echo "Prepping disk ${MONGODB_DISK}"
systemctl stop mongodb 2> /dev/null
umount -f ${MONGODB_DISK}
mkfs.ext4 -F ${MONGODB_DISK} || exit 1

echo "Copying Mongodb Configuration"
cp ${BENCH_DIR}/{mongod.conf,mongodb.service,mongodb.slice} ${DATA_DIR}

echo "Configuring Mongodb"
MONGO_DATA_DIR=$(readlink -f ${DATA_DIR}/mongodb)
sed -i "s|dbPath: /data/db|dbPath: ${MONGO_DATA_DIR}|" ${DATA_DIR}/mongod.conf
ln -sf $(readlink -f ${DATA_DIR}/mongod.conf) /etc
cp /etc/mongod.conf ${DATA_DIR}/mongod.conf.old
cp -f ${DATA_DIR}/mongodb.service /etc/systemd/system
cp -f ${DATA_DIR}/mongodb.slice /etc/systemd/system
systemctl daemon-reload || exit 1

echo "Enabling mongodb service.."
systemctl enable mongodb.slice mongodb.service
start_mongodb;

#YCSB Workload params
echo "Configuring YCSB.."

#scale number of record linearly 80Million records consume 121G space
YCSB_RECORD_COUNT=$(echo  ${DISK_SIZE} \* 80000000 / \( 1024 \* 1024 \* 1024 \* 121 \)  | bc )
# cap the record count to 80M
if [ "${YCSB_RECORD_COUNT}" -gt "80000000" ]; then
    YCSB_RECORD_COUNT=80000000
fi
YCSB_OPERATION_COUNT=${YCSB_RECORD_COUNT}
echo "YCSB Recound count ${YCSB_RECORD_COUNT}"

echo "Configuring Bench.."
sed -i "s|<bench-path>|${BENCH_DIR}|" ${DATA_DIR}/mglru-benchmark.service
cp -f ${DATA_DIR}/mglru-benchmark.service /etc/systemd/system
systemctl daemon-reload

echo "Generating Bench Configuration"
cat > ${DATA_DIR}/bench.conf <<-EOF
MONGODB_DISK=${MONGODB_DISK}
MONGO_DATA_DIR=${MONGO_DATA_DIR}
DATA_DIR=${DATA_DIR}
DISK_IMAGE=${DISK_IMAGE}
export YCSB_HOME=${YCSB_HOME}
RESULTS_DIR=${RESULTS_DIR}
#YCSB Workload params
YCSB_RECORD_COUNT=${YCSB_RECORD_COUNT}
YCSB_OPERATION_COUNT=${YCSB_OPERATION_COUNT}
KERNEL_BOOT_ARGS="${KERNEL_BOOT_ARGS}"
QEMU_IMG=${QEMU_IMG}
EOF

MONGODB_URL=$(get_mongodb_url)
echo "Will be connecting to mongodb at ${MONGODB_URL}"
echo "Done Setting up the bench"
echo "Starting to populate the mongodb instance"
${BENCH_DIR}/ycsb_load.sh
