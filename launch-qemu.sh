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
