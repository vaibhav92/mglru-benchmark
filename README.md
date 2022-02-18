# mglru-benchmark
MGLRU Kernel Mongodb Test Bench for RHEL 8.4

!! Warning: This code comes with absolutely no warrantey or any sort. Use at your own risk !!

# Prequisite
* Red Hat Enterprise Linux 8.4 
  Have only tested this on this specific Distro. However can work on other RHEL based distros to.

* Disk with atleast 128GiB space to host Mongodb Data Files 
* Atleast 140GiB of disk space on the partition that will run the bench

## Running the bench
**!! Warning: Contents of `MONGODB_DISK` are formatted and lost**

```
 # cd <home-dir>
 # export MONGODB_DISK=/dev/<disk-name>; curl https://raw.githubusercontent.com/vaibhav92/mglru-benchmark/v5.17_kernel/build.sh | bash -s 
```
This would install+pull+build the needed dependecies and start the MGLRU benchmark after booting into the base kernel

## Stopping the test
```
# systemctl stop mglru-benchmark; 
# systemctl disable mglru-benchmark;
```

## Collecting results
Results will be collected in the directory `<home-dir>/mglru/result`

## Analyzing results
Provided `results.py` python script can traverse the results directory and generate a CSV file out the stdout which can then be imported in the analysis tool

```
# python3 results.py <home-dir>/mglru/result  > results.csv
```
  
#Test-Methodlogy


Setup
-----
1. Pull & Build testing artifact v5.16 Base Kernel, MGLRU Kernel,
   MongoDB, YCSB & Qemu for qemu-img tools
2. Format and mount provided MongoDB Data disk with ext4.
3. Generate Systemd service/slice files for MongoDB and place them into /etc/systemd/system/
4. Generate MongoDB configration pointing to the data disk mount.
5. Start the built MongoDB instance.
6. Ensure that MongoDB is running.
   
Load Test Data
---------------
1. Ensure that MongoDB instance is stopped.
2. Unmount the data disk and reformat it with ext4.
3. Restart MongoDB.
4. Spin off YCSB to load data into the Mongo instance.
5. Stop MongoDB + Unmount data Disk
6. Create a qcow2 image of the data disk and store it with test data.
7. Kexec into base kernel.

Test Phase (Happens at each boot)
---------------------------------
1. Select the distribution to be used for YCSB from
   {"Uniform","Exponential","Zipfan"}
2. Restore the MongoDB qcow2 data disk Image to the disk
3. Mount the data disk and restart MongoDB daemon.
4. Start YCSB to generate the workload on MongoDB.
5. Once finished collect results.
6. Kexec into next-kernel which keeps switching between Base-Kernel &
   MGLRU-Kernel when all three distriutions have been tested.


