# KernelBuildingAndDebug
Set of scripts and instructions for building a debugging a custom kernel

# Build the kernel

First use this script to download and build the kernel. Make sure to update KERNEL_VERSION to your target kernel version:
```
########################################################
# - Which kernel version to download 
# - need to update KERNEL_VERSION
########################################################
export KERNEL_VERSION=5.15.102
export KERNEL_LINK=https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION:0:1}.x/linux-$KERNEL_VERSION.tar.gz


########################################################
# Install packages needed to build/run the custom kernel
########################################################
# - debootstrap -- Debootstrap is a tool used in Debian-based Linux distributions 
#	to install a basic Debian or Ubuntu system into a target directory
apt update -y
apt install -y debootstrap qemu qemu-system-x86 git build-essential qemu-system-x86


########################################################
# Download the kernel sources
########################################################
wget $KERNEL_LINK
tar xfvz linux-$KERNEL_VERSION.tar.gz


########################################################
# Build the kernel
########################################################
# - The make defconfig command generates a default configuration file named .config 
# 	in the current directory that specifies the default values for all the configuration options
# - The first sed command disables KASLR in the config, this is good for debugging/exploit dev;
#	it can be re-enabled when testing production exploit
# - CONFIG_DEBUG_KERNEL seems to already be set to `y` but if not be sure to enable it;
#	we definitely want debugging symbols
cd linux-$KERNEL_VERSION
make defconfig
sed -i 's/CONFIG_RANDOMIZE_BASE=y/CONFIG_RANDOMIZE_BASE=n/g' .config
make -j`nproc`
cd ..



########################################################
# Make sure build succeeded
########################################################
file linux-$KERNEL_VERSION/vmlinux | grep 'not stripped' && echo '[+] we got a debug kernel!'
ls linux-$KERNEL_VERSION/arch/x86/boot/bzImage 2>&1 > /dev/null && '[+] echo got a bzImage'
```
# Create the OS Image

Next, use this slightly modified syzkaller script to create an OS image. Make sure to update the RELEASE variable to your target Ubuntu version. Also, run this script in a folder adjacent to the kernel sources, I named folder ubuntu-image:
```
#!/usr/bin/env bash
# Copyright 2016 syzkaller project authors. All rights reserved.
# Use of this source code is governed by Apache 2 LICENSE that can be found in the LICENSE file.

# create-image.sh creates a minimal Debian Linux image suitable for syzkaller.

# -eux means `exit on error`, `error on undefined variable`, `xtrace (print each command to terminal)`
set -eux


# Create a minimal Debian distribution in a directory.
DIR=chroot
PREINSTALL_PKGS=openssh-server,curl,tar,gcc,libc6-dev,time,strace,sudo,less,psmisc,net-tools

# If ADD_PACKAGE is not defined as an external environment variable, use our default packages
if [ -z ${ADD_PACKAGE+x} ]; then
    ADD_PACKAGE="make,sysbench,git,vim,tmux,usbutils,tcpdump"
fi

# Variables affected by options
# http://archive.ubuntu.com/ubuntu/
ARCH=$(uname -m)
RELEASE=focal       # (UPDATE THIS!! focal, xenial, etc.)
FEATURE=minimal
SEEK=2047
PERF=false

# Display help function
display_help() {
    echo "Usage: $0 [option...] " >&2
    echo
    echo "   -a, --arch                 Set architecture"
    echo "   -d, --distribution         Set on which debian distribution to create"
    echo "   -f, --feature              Check what packages to install in the image, options are minimal, full"
    echo "   -s, --seek                 Image size (MB), default 2048 (2G)"
    echo "   -h, --help                 Display help message"
    echo "   -p, --add-perf             Add perf support with this option enabled. Please set envrionment variable \$KERNEL at first"
    echo
}

while true; do
    if [ $# -eq 0 ];then
    echo $#
    break
    fi
    case "$1" in
        -h | --help)
            display_help
            exit 0
            ;;
        -a | --arch)
        ARCH=$2
            shift 2
            ;;
        -d | --distribution)
        RELEASE=$2
            shift 2
            ;;
        -f | --feature)
        FEATURE=$2
            shift 2
            ;;
        -s | --seek)
        SEEK=$(($2 - 1))
            shift 2
            ;;
        -p | --add-perf)
        PERF=true
            shift 1
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
        *)  # No more options
            break
            ;;
    esac
done

# Handle cases where qemu and Debian use different arch names
case "$ARCH" in
    ppc64le)
        DEBARCH=ppc64el
        ;;
    aarch64)
        DEBARCH=arm64
        ;;
    arm)
        DEBARCH=armel
        ;;
    x86_64)
        DEBARCH=amd64
        ;;
    *)
        DEBARCH=$ARCH
        ;;
esac

# Foreign architecture

FOREIGN=false
if [ $ARCH != $(uname -m) ]; then
    # i386 on an x86_64 host is exempted, as we can run i386 binaries natively
    if [ $ARCH != "i386" -o $(uname -m) != "x86_64" ]; then
        FOREIGN=true
    fi
fi

if [ $FOREIGN = "true" ]; then
    # Check for according qemu static binary
    if ! which qemu-$ARCH-static; then
        echo "Please install qemu static binary for architecture $ARCH (package 'qemu-user-static' on Debian/Ubuntu/Fedora)"
        exit 1
    fi
    # Check for according binfmt entry
    if [ ! -r /proc/sys/fs/binfmt_misc/qemu-$ARCH ]; then
        echo "binfmt entry /proc/sys/fs/binfmt_misc/qemu-$ARCH does not exist"
        exit 1
    fi
fi

# Double check KERNEL when PERF is enabled
if [ $PERF = "true" ] && [ -z ${KERNEL+x} ]; then
    echo "Please set KERNEL environment variable when PERF is enabled"
    exit 1
fi

# If full feature is chosen, install more packages
if [ $FEATURE = "full" ]; then
    PREINSTALL_PKGS=$PREINSTALL_PKGS","$ADD_PACKAGE
fi

sudo rm -rf $DIR
sudo mkdir -p $DIR
sudo chmod 0755 $DIR

# 1. debootstrap stage

DEBOOTSTRAP_PARAMS="--arch=$DEBARCH --include=$PREINSTALL_PKGS --components=main,contrib,non-free $RELEASE $DIR"
if [ $FOREIGN = "true" ]; then
    DEBOOTSTRAP_PARAMS="--foreign $DEBOOTSTRAP_PARAMS"
fi

sudo debootstrap $DEBOOTSTRAP_PARAMS http://archive.ubuntu.com/ubuntu/

# 2. debootstrap stage: only necessary if target != host architecture

if [ $FOREIGN = "true" ]; then
    sudo cp $(which qemu-$ARCH-static) $DIR/$(which qemu-$ARCH-static)
    sudo chroot $DIR /bin/bash -c "/debootstrap/debootstrap --second-stage"
fi

# Set some defaults and enable promtless ssh to the machine for root.
sudo sed -i '/^root/ { s/:x:/::/ }' $DIR/etc/passwd
echo 'T0:23:respawn:/sbin/getty -L ttyS0 115200 vt100' | sudo tee -a $DIR/etc/inittab
#printf '\nauto eth0\niface eth0 inet dhcp\n' | sudo tee -a $DIR/etc/network/interfaces
printf 'network:\n  version: 2\n  ethernets:\n    eth0:\n      dhcp4: true' | sudo tee -a $DIR/etc/netplan/eth0.yaml
echo '/dev/root / ext4 defaults 0 0' | sudo tee -a $DIR/etc/fstab
echo 'debugfs /sys/kernel/debug debugfs defaults 0 0' | sudo tee -a $DIR/etc/fstab
echo 'securityfs /sys/kernel/security securityfs defaults 0 0' | sudo tee -a $DIR/etc/fstab
echo 'configfs /sys/kernel/config/ configfs defaults 0 0' | sudo tee -a $DIR/etc/fstab
echo 'binfmt_misc /proc/sys/fs/binfmt_misc binfmt_misc defaults 0 0' | sudo tee -a $DIR/etc/fstab
echo -en "127.0.0.1\tlocalhost\n" | sudo tee $DIR/etc/hosts
echo "nameserver 8.8.8.8" | sudo tee -a $DIR/etc/resolve.conf
echo "ngunibantu" | sudo tee $DIR/etc/hostname
ssh-keygen -f $RELEASE.id_rsa -t rsa -N ''
sudo mkdir -p $DIR/root/.ssh/
cat $RELEASE.id_rsa.pub | sudo tee $DIR/root/.ssh/authorized_keys

# Add perf support
if [ $PERF = "true" ]; then
    cp -r $KERNEL $DIR/tmp/
    BASENAME=$(basename $KERNEL)
    sudo chroot $DIR /bin/bash -c "apt-get update; apt-get install -y flex bison python-dev libelf-dev libunwind8-dev libaudit-dev libslang2-dev libperl-dev binutils-dev liblzma-dev libnuma-dev"
    sudo chroot $DIR /bin/bash -c "cd /tmp/$BASENAME/tools/perf/; make"
    sudo chroot $DIR /bin/bash -c "cp /tmp/$BASENAME/tools/perf/perf /usr/bin/"
    rm -r $DIR/tmp/$BASENAME
fi

# Add udev rules for custom drivers.
# Create a /dev/vim2m symlink for the device managed by the vim2m driver
echo 'ATTR{name}=="vim2m", SYMLINK+="vim2m"' | sudo tee -a $DIR/etc/udev/rules.d/50-udev-default.rules

# Build a disk image
dd if=/dev/zero of=$RELEASE.img bs=1M seek=$SEEK count=1
sudo mkfs.ext4 -F $RELEASE.img
sudo mkdir -p /mnt/$DIR
sudo mount -o loop $RELEASE.img /mnt/$DIR
sudo cp -a $DIR/. /mnt/$DIR/.
sudo umount /mnt/$DIR
sudo rm -rf /mnt/$DIR
```
# Make a Wrapper Script to Launch the QEMU VM
```
export KERNEL_VERSION="5.15.102"
export IMAGE="ubuntu-image"

# -m -- sets the amount of memory for the vm
# -s -- enables kernel debugging
# -smp -- sets the number of processors (1 may be ideal for kernel debugging)
# -kerenl -- path to the kernl
# -append -- boot options
# -drive -- path to the OS image
# -net -- set up port forwarding for ssh
# -pidfile -- Store the QEMU process PID in file
qemu-system-x86_64 \
	-m 2G \
	-s \
	-smp 1 \
	-kernel linux-$KERNEL_VERSION/arch/x86/boot/bzImage \
	-append "console=ttyS0 root=/dev/sda earlyprintk=serial net.ifnames=0" \
	-drive file=$IMAGE/focal.img,format=raw \
	-net user,host=10.0.2.10,hostfwd=tcp:127.0.0.1:10021-:22 \
	-net nic,model=e1000 \
	-nographic \
	-pidfile vm.pid \
	2>&1 | tee vm.log
```
# Make a Wrapper Script to Connect to SSH
```
IMAGE="ubuntu-image"
ssh -i $IMAGE/focal.id_rsa -p 10021 -o "StrictHostKeyChecking no" root@localhost

Install GEF and Update .gdbinit File

bash -c "$(curl -fsSL https://gef.blah.cat/sh)"
file /path/to/your/vmlinux
target remote localhost:1234
```
# References
* https://www.josehu.com/memo/2021/01/02/linux-kernel-build-debug.html
* https://github.com/google/syzkaller/blob/master/tools/create-image.sh
* greetz to @fabiusartrel
