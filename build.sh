#!/bin/bash

MONGODB_DISK=/dev/sdc

KERNEL_SOURCE_MGLRU=https://linux-mm.googlesource.com/page-reclaim
KERNEL_SOURCE_REF_MGLRU=refs/changes/49/1549/1
KERNEL_SOURCE_NON_MGLRU=https://github.com/torvalds/linux/
KERNEL_SOURCE_REF_NON_MGLRU=v5.16
KERNEL_BOOT_ARGS="transparent_hugepage=never systemd.unified_cgroup_hierarchy=1"
KERNEL_CONFIG_BASE="https://gist.githubusercontent.com/vaibhav92/aff0640c1462f641334d453fd0939144/raw/462e21ae10b9e3b7f7faeddfeb41c38d911985c3"
KERNEL_CONFIG_MGLRU="${KERNEL_CONFIG_BASE}/config-mglru"
KERNEL_CONFIG_NON_MGLRU="${KERNEL_CONFIG_BASE}/config-non-mglru"


MONGODB_SOURCE=https://github.com/mongodb/mongo.git
MONGODB_SOURCE_REF="r5.0.6"

YCSB_SOURCE=https://github.com/vaibhav92/YCSB.git
YCSB_SOURCE_REF=mongodb-domain-sockets

MGLRU_BENCH_SOURCE=https://github.com/vaibhav92/mglru-benchmark.git
MGLRU_BENCH_SOURCE_REF=""

MONGODB_CONFIG_BASE="https://gist.github.com/vaibhav92/6952d5ec12e7ec3c15165e4212eeff90/raw/cd35d8bb5f669e29a1b00846cae72d428a85448d"
MGLRU_BENCH_SERVICE="https://gist.githubusercontent.com/vaibhav92/ad1320a7cd0293e2dd8821bccf27271d/raw/7c0c408434a432f01c1b3a9bed38c80b1af00534/mglru-benchmark.service"



if [ ! -b "${MONGODB_DISK}" ];then
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

#install dependencies for RHEL 8.4
echo "Installing dependencies...."
dnf install -y git gcc make flex bison openssl-devel python2 python36 python36-devel\
    maven qemu-img libcurl-devel gcc-c++ elfutils-libelf-devel tar e2fsprogs util-linux curl numactl dwarves || exit 1

pushd .
mkdir mglru 2>/dev/null
cd mglru

#create needed dirs
mkdir -p linux mongo ycsb data bench results data/mongodb 2> /dev/null

DATA_DIR=$(readlink -f data)
RESULTS_DIR=$(readlink -f results)
DISK_IMAGE=${DATA_DIR}/mongodb.qcow2

#YCSB Workload params
#scale number of record linearly 80Million records consume 121G space
YCSB_RECORD_COUNT=$(echo  ${DISK_SIZE} \* 80000000 / \( 1024 \* 1024 \* 1024 \* 121 \)  | bc )
YCSB_OPERATION_COUNT=${YCSB_RECORD_COUNT}


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

echo "Downloading Mongodb Configuration"
curl -L "${MONGODB_CONFIG_BASE}/{mongod.conf,mongodb.service,mongodb.slice}" -o "data/#1"
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi

echo "Downloading MGLRU Bench from "${MGLRU_BENCH_SOURCE} Ref:${MGLRU_BENCH_SOURCE_REF}
[ -d 'bench/.git' ] || git -C bench init
git -C bench fetch ${MGLRU_BENCH_SOURCE} ${MGLRU_BENCH_SOURCE_REF}
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
git -C bench checkout FETCH_HEAD
curl -L "${MGLRU_BENCH_SERVICE}" -o "data/mglru-benchmark.service"
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi

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
YCSB_HOME=$(readlink -f .)
cd ..

cd linux
if [ ! -f "${DATA_DIR}/vmlinux-non-mglru" ]; then
    #build the non-mglru  kernel
    echo "Building NON-MGLRU Kernel"
    git fetch ${KERNEL_SOURCE_NON_MGLRU} ${KERNEL_SOURCE_REF_NON_MGLRU} && git checkout FETCH_HEAD
    echo "Downloading kernel config"
    curl -L -qo .config ${KERNEL_CONFIG_NON_MGLRU}
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    make olddefconfig && make -j 32 vmlinux modules && make modules_install
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    cp -f vmlinux ${DATA_DIR}/vmlinux-non-mglru
    dracut --kver $(make kernelrelease)  --force ${DATA_DIR}/initrd-non-mglru
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    cp -f .config ${DATA_DIR}/config-non-mglru
    make distclean
fi


#build the mglru kernel
if [ ! -f "${DATA_DIR}/vmlinux-mglru" ]; then
    echo "Building MGLRU Kernel"
    # git fetch ${KERNEL_SOURCE_MGLRU} ${KERNEL_SOURCE_REF_MGLRU} && git checkout FETCH_HEAD
    echo "Downloading kernel config"
    # curl -L -qo .config ${KERNEL_CONFIG_MGLRU}
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    # make olddefconfig && make -j 32 vmlinux modules && make modules_install
    make -j 32 vmlinux modules && make modules_install
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    cp -f vmlinux ${DATA_DIR}/vmlinux-mglru
    dracut --kver $(make kernelrelease)  --force ${DATA_DIR}/initrd-mglru
    if [ "$?" -ne "0" ] ;then popd ;exit 1;fi
    cp -f .config ${DATA_DIR}/config-mglru
    make distclean
fi
cd ..

echo "Configuring Mongodb"
MONGO_DATA_DIR=$(readlink -f ${DATA_DIR}/mongodb)
sed -i "s|dbPath: /data/db|dbPath: ${MONGO_DATA_DIR}|" ${DATA_DIR}/mongod.conf
ln -sf $(readlink -f ${DATA_DIR}/mongod.conf) /etc
cp -f ${DATA_DIR}/mongodb.service /etc/systemd/system
cp -f ${DATA_DIR}/mongodb.slice /etc/systemd/system
systemctl daemon-reload

echo "Prepping disk ${MONGODB_DISK}"
umount ${MONGODB_DISK}
mkfs.ext4 -F ${MONGODB_DISK}
mount ${MONGODB_DISK} ${DATA_DIR}/mongodb
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi	

echo "Enabling mongodb service.."
systemctl enable mongodb.slice mongodb.service
systemctl restart mongodb.service
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi


sleep 1
echo "Checking if mongodb is active"
systemctl is-active mongodb.service
if [ "$?" -ne "0" ] ;then popd ;exit 1;fi


echo "Configuring Bench.."
BENCH_DIR=$(readlink -f bench)
sed -i "s|<bench-path>|${BENCH_DIR}|" ${DATA_DIR}/mglru-benchmark.service
cp -f ${DATA_DIR}/mglru-benchmark.service /etc/systemd/system
systemctl daemon-reload


#echo "Generating Bench Configuration"
cat > ${DATA_DIR}/bench.conf <<-EOF
DISK_DEVICE=${MONGODB_DISK}
MOUNT_POINT=${MONGO_DATA_DIR}
DATA_DIR=${DATA_DIR}
DISK_IMAGE=${DISK_IMAGE}
export YCSB_HOME=${YCSB_HOME}
RESULTS_DIR=${RESULTS_DIR}
#YCSB Workload params
YCSB_RECORD_COUNT=${YCSB_RECORD_COUNT}
YCSB_OPERATION_COUNT=${YCSB_OPERATION_COUNT}
KERNEL_BOOT_ARGS=${KERNEL_BOOT_ARGS}
EOF

popd
