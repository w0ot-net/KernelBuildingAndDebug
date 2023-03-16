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
sed -i 's/# CONFIG_DEBUG_INFO is not set/CONFIG_DEBUG_INFO=y/g' .config
make -j`nproc`
cd ..



########################################################
# Make sure build succeeded
########################################################
file linux-$KERNEL_VERSION/vmlinux | grep 'not stripped' && echo '[+] we got a debug kernel!'
ls linux-$KERNEL_VERSION/arch/x86/boot/bzImage 2>&1 > /dev/null && echo got a bzImage

