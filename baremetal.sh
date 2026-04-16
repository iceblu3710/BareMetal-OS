#!/usr/bin/env bash

set +e
export EXEC_DIR="$PWD"
export OUTPUT_DIR="$EXEC_DIR/sys"

cmd=( qemu-system-x86_64
	-machine q35 #,hpet=off

# CPU (only 1 cpu type should be uncommented)
	-smp sockets=1,cpus=4
	-cpu Westmere
#	-cpu Westmere,x2apic,pdpe1gb
#	-cpu host -enable-kvm

# RAM
	-m 256 # Value is in Megabytes

# Video
	-device VGA,edid=on,xres=1024,yres=768

# Network configuration. Use one controller on testnet1 and, optionally, one on testnet2
	-netdev socket,id=testnet1,listen=:1234
#	-netdev socket,id=testnet2,listen=:1235
# Intel 82540EM
#	-device e1000,netdev=testnet1,mac=10:11:12:08:25:40
#	-device e1000,netdev=testnet2,mac=11:12:13:08:25:40
# Intel 82574L
#	-device e1000e,netdev=testnet1,mac=10:11:12:08:25:74
#	-device e1000e,netdev=testnet2,mac=11:12:13:08:25:74
# VIRTIO
	-device virtio-net-pci,netdev=testnet1,mac=10:11:12:00:1A:F4 #,disable-legacy=on,disable-modern=false
#	-device virtio-net-pci,netdev=testnet2,mac=11:12:13:00:1A:F4 #,disable-legacy=on,disable-modern=false

# Disk configuration. Use one controller.
	-drive id=disk0,file="sys/baremetal_os.img",if=none,format=raw
# NVMe
#	-device nvme,serial=12345678,drive=disk0
# AHCI
#	-device ide-hd,drive=disk0
# VIRTIO-Block
	-device virtio-blk,drive=disk0,serial=BMBOOT000 #,disable-legacy=on,disable-modern=false
# VIRTIO-SCSI
#	-device virtio-scsi-pci #,disable-legacy=on,disable-modern=false
#	-device scsi-hd,drive=disk0
# Floppy
#	-drive format=raw,file="sys/floppy.img",index=0,if=floppy

# USB
#	-device qemu-xhci # Supports MSI-X
#	-device nec-usb-xhci # Supports MSI-X and MSI

# HID
#	-device usb-mouse
#	-device usb-kbd
#	-device virtio-keyboard

# Serial configuration
# Expose serial port to telnet
#	-serial telnet:localhost:8023,server,nowait,logfile="sys/serial.log"
# Output serial to file
	-serial file:"sys/serial.log"
# Output serial to console
#	-chardev stdio,id=char0,logfile="sys/serial.log",signal=off
#	-serial chardev:char0

# Debugging
# Enable monitor mode
	-monitor telnet:localhost:8086,server,nowait
# Enable GDB debugging
#	-s
# Wait for GDB before starting execution
#	-S
# Output network traffic to file
#	-object filter-dump,id=testnet,netdev=testnet,file=net.pcap
# Trace options
#	-trace "e1000e_core*"
#	-trace "virt*"
#	-trace "apic*"
#	-trace "msi*"
#	-trace "usb*"
#	-d trace:memory_region_ops_* # Or read/write
#	-d int # Display interrupts
# Prevent QEMU for resetting (triple fault)
#	-no-shutdown -no-reboot
)

# see if APPS was defined
# eg APPS="hello.app systest.app" ./baremetal.sh setup
# if APPS is empty then supply the default apps
# this allows the user to build their own apps and have
# them installed in the BMFS
if [ "x$APPS" = x ]; then
	APPS="hello.app sysinfo.app systest.app"
	if [ "$(uname)" != "Darwin" ]; then
		APPS="$APPS helloc.app raytrace.app cube3d.app"
	fi
fi
# see if BMFS_SIZE was defined for custom disk sizes
if [ "x$BMFS_SIZE" = x ]; then
	BMFS_SIZE=128
fi
# see if DATAFS_SIZE was defined for custom ext2 data disk sizes
if [ "x$DATAFS_SIZE" = x ]; then
	DATAFS_SIZE=512
fi
# see if DATAFS_FS was defined for filesystem format type
if [ "x$DATAFS_FS" = x ]; then
	DATAFS_FS=ext3
fi
# set a predictable serial for the data disk to simplify kernel selection logic
if [ "x$DATAFS_SERIAL" = x ]; then
	DATAFS_SERIAL=BMDATA0001
fi
# expected NVS device index for the data disk inside the kernel
if [ "x$DATAFS_NVS_ID" = x ]; then
	DATAFS_NVS_ID=1
fi
# set ENABLE_DATAFS=0 to run without attaching the ext data disk
if [ "x$ENABLE_DATAFS" = x ]; then
	ENABLE_DATAFS=1
fi

function baremetal_clean {
	rm -rf src
	rm -rf sys
}

function baremetal_setup {
	echo -e "BareMetal OS Setup\n==================="
	baremetal_clean

	mkdir src
	mkdir sys

	echo -n "Pulling code from GitHub"

	if [ "$1" = "dev" ]; then
		echo -n " (Dev Env)... "
		setup_args=" -q"
	else
		echo -n "... "
		setup_args=" -q --depth 1"
	fi

	cd src
	git clone https://github.com/ReturnInfinity/Pure64.git $setup_args
	git clone https://github.com/ReturnInfinity/BareMetal.git $setup_args
	git clone https://github.com/ReturnInfinity/BareMetal-Monitor.git $setup_args
	git clone https://github.com/ReturnInfinity/BMFS.git $setup_args
	git clone https://github.com/ReturnInfinity/BareMetal-Demo.git $setup_args
	cd ..
	echo "OK"

	if [ -x "$(command -v mformat)" ]; then
		echo -n "Downloading UEFI firmware... "
		cd sys
		if [ -x "$(command -v curl)" ]; then
			curl -s -O https://cdn.download.clearlinux.org/image/OVMF.fd
		else
			wget -q https://cdn.download.clearlinux.org/image/OVMF.fd
		fi
		cd ..
		echo "OK"
	else
		echo "Skipping UEFI firmware download due to missing mtools..."
	fi

	echo -n "Preparing dependancies... "
	cd src/BareMetal-Monitor
	./setup.sh
	cd ../..
	cd src/BareMetal-Demo
	./setup.sh
	cd ../..
	echo "OK"

	baremetal_build

	echo -n "Copying software to disk image... "
	baremetal_install
	baremetal_install_demos
	echo "OK"

	echo -e "\nSetup Complete. Use './baremetal.sh run' to start."
}

# Initialize disk images
function init_imgs { # arg 1 is BMFS size in MiB
	echo -n "Creating disk image files... "
	cd sys
	dd if=/dev/zero of=bmfs.img count=$1 bs=1048576 > /dev/null 2>&1
	dd if=/dev/zero of=bmfs-lite.img count=1 bs=1048576 > /dev/null 2>&1
	if [ -x "$(command -v mformat)" ]; then
		mformat -t 128 -h 2 -s 1024 -C -F -i fat32.img
		mmd -i fat32.img ::/EFI > /dev/null 2>&1
		mmd -i fat32.img ::/EFI/BOOT > /dev/null 2>&1
		retVal=$?
		if [ $retVal -ne 0 ]; then
			echo -n "no UEFI support (due to bad mtools), "
		fi
		echo "\EFI\BOOT\BOOTX64.EFI" > startup.nsh
		mcopy -i fat32.img startup.nsh ::/
		rm startup.nsh
	else
		dd if=/dev/zero of=fat32.img count=128 bs=1048576 > /dev/null 2>&1
	fi
	echo "OK"

	cd ..
}

# Append the optional ext data disk to a qemu argument array
function append_datafs_cmd { # arg 1 is array variable name
	local -n qcmd_ref=$1
	if [ "$ENABLE_DATAFS" != "1" ]; then
		return
	fi
	if [ ! -f "sys/ext_data.img" ]; then
		echo "Warning: sys/ext_data.img is missing. Use './baremetal.sh datafs' to create it."
		return
	fi
	qcmd_ref+=( -drive id=disk1,file="sys/ext_data.img",if=none,format=raw )
	qcmd_ref+=( -device virtio-blk,drive=disk1,serial=$DATAFS_SERIAL )
}

# Initialize data disk image for a Linux ext2/3 filesystem
function init_data_img { # arg 1 is DataFS size in MiB
	echo -n "Creating data disk image file... "
	cd sys
	dd if=/dev/zero of=ext_data.img count=$1 bs=1048576 > /dev/null 2>&1
	if [ -x "$(command -v mke2fs)" ]; then
		mke2fs -q -t "$DATAFS_FS" -L BMDATA ext_data.img
		echo "OK ($DATAFS_FS formatted)"
	else
		echo "OK (unformatted, install e2fsprogs for auto-format)"
	fi
	cat > ext_data.meta <<EOF
DATAFS_FS=$DATAFS_FS
DATAFS_SIZE_MIB=$1
DATAFS_SERIAL=$DATAFS_SERIAL
DATAFS_NVS_ID=$DATAFS_NVS_ID
EOF
	cd ..
}

function update_dir {
	echo "Updating $1..."
	cd "$1"
	git pull -q
	cd "$EXEC_DIR"
}

function baremetal_update {
	git pull -q
	baremetal_src_check
	update_dir "src/Pure64"
	update_dir "src/BareMetal"
	update_dir "src/BareMetal-Monitor"
	update_dir "src/BMFS"
	update_dir "src/BareMetal-Demo"
}

function build_dir {
	cd "$1"
	if [ -e "build.sh" ]; then
		./build.sh || { cd "$EXEC_DIR"; return 1; }
	fi
	if [ -e "install.sh" ]; then
		./install.sh || { cd "$EXEC_DIR"; return 1; }
	fi
	if [ -e "Makefile" ]; then
		make --quiet || { cd "$EXEC_DIR"; return 1; }
	fi
	if ! compgen -G "bin/*" > /dev/null; then
		echo "Build output missing in $1/bin"
		cd "$EXEC_DIR"
		return 1
	fi
	mv bin/* "${OUTPUT_DIR}" || { cd "$EXEC_DIR"; return 1; }
	cd "$EXEC_DIR"
	return 0
}

# Build the source code and create the software files
function baremetal_build {
	baremetal_src_check
	echo -n "Assembling source code... "
	build_dir "src/Pure64" || { echo "FAILED"; exit 1; }
	build_dir "src/BareMetal" || { echo "FAILED"; exit 1; }
	build_dir "src/BareMetal-Monitor" || { echo "FAILED"; exit 1; }
	build_dir "src/BMFS" || { echo "FAILED"; exit 1; }
	build_dir "src/BareMetal-Demo" || { echo "FAILED"; exit 1; }
	echo "OK"

	init_imgs $BMFS_SIZE
	init_data_img $DATAFS_SIZE

	cd "$OUTPUT_DIR"

	# Inject a program binary into to the kernel (ORG 0x001E0000)
	if [ "$#" -ne 1 ]; then
		cat pure64-bios.sys kernel.sys monitor.bin > software-bios.sys
		cat pure64-uefi.sys kernel.sys monitor.bin > software-uefi.sys
	else
		if [ -f $1 ]; then
			cat pure64-bios.sys kernel.sys $1 > software-bios.sys
			cat pure64-uefi.sys kernel.sys $1 > software-uefi.sys
		else
			echo "$1 does not exist. Skipping binary injection"
		fi
	fi
	softwaresize=$(wc -c <software-bios.sys)
	if [ $softwaresize -gt 32768 ]; then
		echo "Warning - BIOS binary is larger than 32768 bytes!"
	fi
	softwaresize=$(wc -c <software-uefi.sys)
	if [ $softwaresize -gt 32768 ]; then
		echo "Warning - UEFI binary is larger than 32768 bytes!"
	fi

	# Copy software to BMFS for BIOS loading
	dd if=software-bios.sys of=bmfs.img bs=4096 seek=2 conv=notrunc > /dev/null 2>&1

	# Prep UEFI loader
	cp uefi.sys BOOTX64.EFI
	dd if=software-uefi.sys of=BOOTX64.EFI bs=4096 seek=1 conv=notrunc > /dev/null 2>&1
	dd if=bmfs-lite.img of=BOOTX64.EFI bs=1024 seek=64 conv=notrunc > /dev/null 2>&1

	dd if=/dev/zero of=floppy.img count=2880 bs=512 > /dev/null 2>&1

	echo -n "Formatting BMFS disk... "
	./bmfs bmfs.img format
	echo "OK"

	cd ..
}

# Install system software (boot sector, Pure64, kernel) to various storage images
function baremetal_install {
	baremetal_sys_check
	cd "$OUTPUT_DIR"

	# Copy UEFI boot to disk image
	if [ -x "$(command -v mcopy)" ]; then
		mcopy -oi fat32.img BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI > /dev/null 2>&1
		retVal=$?
		if [ $retVal -ne 0 ]; then
			echo -n "no UEFI support (due to bad mtools), "
		fi
	fi

	# Copy first 3 bytes of MBR (jmp and nop)
	dd if=bios.sys of=fat32.img bs=1 count=3 conv=notrunc > /dev/null 2>&1
	# Copy MBR code starting at offset 90
	dd if=bios.sys of=fat32.img bs=1 skip=90 seek=90 count=356 conv=notrunc > /dev/null 2>&1
	# Copy Bootable flag (in case of no mtools)
	dd if=bios.sys of=fat32.img bs=1 skip=510 seek=510 count=2 conv=notrunc > /dev/null 2>&1

	# Create FAT32/BMFS hybrid disk
	cat fat32.img bmfs.img > baremetal_os.img

	# Create Floppy bootable system disk
	cat bios-floppy.sys software-bios.sys > floppy.sys
	dd if=floppy.sys of=floppy.img conv=notrunc > /dev/null 2>&1

	# Create BMFS BIOS disk for hypervisors
	cp bmfs.img baremetal_os_bios.img
	# Copy first 3 bytes of MBR (jmp and nop)
	dd if=bios-novideo.sys of=baremetal_os_bios.img bs=1 count=3 conv=notrunc > /dev/null 2>&1
	# Copy MBR code starting at offset 90
	dd if=bios-novideo.sys of=baremetal_os_bios.img bs=1 skip=90 seek=90 count=356 conv=notrunc > /dev/null 2>&1
	# Copy Bootable flag (in case of no mtools)
	dd if=bios-novideo.sys of=baremetal_os_bios.img bs=1 skip=510 seek=510 count=2 conv=notrunc > /dev/null 2>&1
	# Copy software (Pure64, kernel, etc) to disk
	dd if=software-bios.sys of=baremetal_os_bios.img bs=4096 seek=2 conv=notrunc > /dev/null 2>&1

	cd ..
}

# Copy demos to disk and RAM drive images, update file disk images
function baremetal_install_demos {
	baremetal_sys_check
	cd "$OUTPUT_DIR"

	# Build disk image
	for app in $APPS; do
		./bmfs bmfs.img write $app
	done

	# Build RAM drive image
	./bmfslite bmfs-lite.img initialize
	for app in $APPS; do
		./bmfslite bmfs-lite.img write $app
	done

	# Create FAT32/BMFS hybrid disk
	cat fat32.img bmfs.img > baremetal_os.img

	# Copy RAM drive image
	dd if=bmfs-lite.img of=BOOTX64.EFI bs=1024 seek=64 conv=notrunc > /dev/null 2>&1
	dd if=bmfs-lite.img of=floppy.img bs=1024 seek=64 conv=notrunc > /dev/null 2>&1

	# Copy UEFI boot + RAM Drive to disk image
	if [ -x "$(command -v mcopy)" ]; then
		mcopy -oi fat32.img BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI > /dev/null 2>&1
		retVal=$?
		if [ $retVal -ne 0 ]; then
			echo -n "no UEFI support (due to bad mtools), "
		fi
	fi

	# Create FAT32/BMFS hybrid disk
	cat fat32.img bmfs.img > baremetal_os.img

	cd ..
}

function baremetal_run {
	baremetal_sys_check
	echo "Starting QEMU..."

	local qcmd=( "${cmd[@]}" )
	append_datafs_cmd qcmd
	qcmd+=( -name "BareMetal OS" )

	"${qcmd[@]}" #execute the cmd string
}

function baremetal_run-uefi {
	baremetal_sys_check
	echo "Starting QEMU (UEFI)..."

	local qcmd=( "${cmd[@]}" )
	append_datafs_cmd qcmd
	qcmd+=( -bios sys/OVMF.fd )
	qcmd+=( -name "BareMetal OS UEFI" )

	#execute the cmd string
	if [ -x "$(command -v mformat)" ]; then
		"${qcmd[@]}"
	else
		echo -n "Unable to run UEFI image due to missing mtools"
	fi
}

function baremetal_run_netclient {
	baremetal_sys_check
	# Make a copy of the latest disk image
	cp sys/baremetal_os.img sys/baremetal_os2.img
	# Start up a VM and connect to the first instance
	echo "Starting QEMU..."
	cmd=( qemu-system-x86_64
		-machine q35
		-name "BareMetal OS (Second Instance)"
		-m 256
		-smp sockets=1,cpus=4
		-netdev socket,id=testnet1,connect=127.0.0.1:1234
		-device e1000,netdev=testnet1,mac=10:11:12:13:CA:FE
#		-netdev socket,id=testnet2,connect=127.0.0.1:1235
#		-device e1000,netdev=testnet2,mac=10:11:12:13:CA:FF
		-drive id=disk0,file="sys/baremetal_os2.img",if=none,format=raw
		-device ahci,id=ahci
		-device ide-hd,drive=disk0,bus=ahci.0
	)
	"${cmd[@]}"
}

function baremetal_vdi {
	baremetal_sys_check
	echo "Creating VDI image..."
	VDI="3C3C3C2051454D5520564D205669727475616C204469736B20496D616765203E3E3E0A00000000000000000000000000000000000000000000000000000000007F10DABE010001008001000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020000000600000000000000000000000000000002000000000000000000100000000000001000000000000001000004000000AE8AA5DE02E79043BE0B20DA0E2863EC00D36EACC7B88D4AA988CF098BC1C90200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

	qemu-img convert -O vdi "$OUTPUT_DIR/baremetal_os.img" "$OUTPUT_DIR/BareMetal_OS.vdi"

	echo $VDI > "$OUTPUT_DIR/VDI_UUID.hex"
	xxd -r -p "$OUTPUT_DIR/VDI_UUID.hex" "$OUTPUT_DIR/VDI_UUID.bin"

	dd if="$OUTPUT_DIR/VDI_UUID.bin" of="$OUTPUT_DIR/BareMetal_OS.vdi" count=1 bs=512 conv=notrunc > /dev/null 2>&1

	rm "$OUTPUT_DIR/VDI_UUID.hex"
	rm "$OUTPUT_DIR/VDI_UUID.bin"
}

function baremetal_vmdk {
	baremetal_sys_check
	echo "Creating VMDK image..."
	qemu-img convert -O vmdk "$OUTPUT_DIR/baremetal_os.img" "$OUTPUT_DIR/BareMetal_OS.vmdk"
}

function baremetal_vpc {
	baremetal_sys_check
	echo "Creating VPC image..."
	qemu-img convert -O vpc "$OUTPUT_DIR/baremetal_os.img" "$OUTPUT_DIR/BareMetal_OS.vpc"
}

function baremetal_bnr {
	baremetal_build
	baremetal_install
	baremetal_install_demos
	baremetal_run
}

function baremetal_bnr-uefi {
	baremetal_build
	baremetal_install
	baremetal_install_demos
	baremetal_run-uefi
}

function baremetal_datafs {
	baremetal_sys_check
	init_data_img "$DATAFS_SIZE"
}

function baremetal_datafs_info {
	baremetal_sys_check
	if [ ! -f "sys/ext_data.img" ]; then
		echo "sys/ext_data.img is missing. Use './baremetal.sh datafs' to create it."
		exit 1
	fi
	if [ -x "$(command -v dumpe2fs)" ]; then
		dumpe2fs -h sys/ext_data.img | sed -n '1,30p'
	else
		echo "Install e2fsprogs to inspect ext_data.img (missing dumpe2fs)"
	fi
}

function baremetal_datafs_manifest {
	baremetal_sys_check
	if [ -f "sys/ext_data.meta" ]; then
		cat sys/ext_data.meta
	else
		echo "sys/ext_data.meta is missing. Use './baremetal.sh datafs' to create it."
		exit 1
	fi
}

function baremetal_datafs_check {
	baremetal_sys_check
	if [ ! -f "sys/ext_data.img" ]; then
		echo "sys/ext_data.img is missing. Use './baremetal.sh datafs' to create it."
		exit 1
	fi
	if [ -x "$(command -v e2fsck)" ]; then
		e2fsck -fn sys/ext_data.img
	else
		echo "Install e2fsprogs to validate ext_data.img (missing e2fsck)"
	fi
}

function baremetal_datafs_replay_test {
	baremetal_sys_check
	if [ ! -f "sys/ext_data.img" ]; then
		echo "sys/ext_data.img is missing. Use './baremetal.sh datafs' to create it."
		exit 1
	fi
	if [ ! -x "$(command -v e2fsck)" ]; then
		echo "Install e2fsprogs to run replay test (missing e2fsck)"
		exit 1
	fi

	cp sys/ext_data.img sys/ext_data_replay.img

	# Mark the copied image as dirty to exercise recovery-oriented fsck flow.
	if [ -x "$(command -v debugfs)" ]; then
		debugfs -w -R "dirty_filesys" sys/ext_data_replay.img > /dev/null 2>&1
	fi

	echo "Running replay-oriented fsck on sys/ext_data_replay.img ..."
	e2fsck -fy sys/ext_data_replay.img | tee sys/ext_data_replay.log
}

function baremetal_datafs_populate {
	baremetal_sys_check
	if [ ! -f "sys/ext_data.img" ]; then
		echo "sys/ext_data.img is missing. Use './baremetal.sh datafs' to create it."
		exit 1
	fi
	if [ ! -x "$(command -v debugfs)" ]; then
		echo "Install e2fsprogs to populate ext_data.img (missing debugfs)"
		exit 1
	fi

	tmp_payload=$(mktemp)
	cat > "$tmp_payload" <<'EOF'
BareMetal ext3 payload v1
path=/bmtest/smoke/probe.txt
EOF

	# Create deterministic content used by future kernel-side read/write tests
	debugfs -w -R "mkdir /bmtest" sys/ext_data.img > /dev/null 2>&1
	debugfs -w -R "mkdir /bmtest/smoke" sys/ext_data.img > /dev/null 2>&1
	debugfs -w -R "write $tmp_payload /bmtest/smoke/probe.txt" sys/ext_data.img > /dev/null

	if [ -x "$(command -v sha256sum)" ]; then
		sha256sum "$tmp_payload" | awk '{print $1}' > sys/ext_data_expected_probe.sha256
	elif [ -x "$(command -v shasum)" ]; then
		shasum -a 256 "$tmp_payload" | awk '{print $1}' > sys/ext_data_expected_probe.sha256
	fi

	rm -f "$tmp_payload"
	echo "Wrote /bmtest/smoke/probe.txt to sys/ext_data.img"
	if [ -f "sys/ext_data_expected_probe.sha256" ]; then
		echo "Wrote expected hash to sys/ext_data_expected_probe.sha256"
	fi
}

function baremetal_datafs_verify_probe {
	baremetal_sys_check
	if [ ! -f "sys/ext_data.img" ]; then
		echo "sys/ext_data.img is missing. Use './baremetal.sh datafs' to create it."
		exit 1
	fi
	if [ ! -x "$(command -v debugfs)" ]; then
		echo "Install e2fsprogs to verify probe payload (missing debugfs)"
		exit 1
	fi
	if [ ! -f "sys/ext_data_expected_probe.sha256" ]; then
		echo "sys/ext_data_expected_probe.sha256 is missing. Run './baremetal.sh datafs-populate' first."
		exit 1
	fi

	tmp_actual=$(mktemp)
	debugfs -R "cat /bmtest/smoke/probe.txt" sys/ext_data.img > "$tmp_actual" 2>/dev/null

	if [ -x "$(command -v sha256sum)" ]; then
		actual_hash=$(sha256sum "$tmp_actual" | awk '{print $1}')
	elif [ -x "$(command -v shasum)" ]; then
		actual_hash=$(shasum -a 256 "$tmp_actual" | awk '{print $1}')
	else
		rm -f "$tmp_actual"
		echo "Missing sha256 tool (sha256sum/shasum)"
		exit 1
	fi

	expected_hash=$(tr -d ' \n\r' < sys/ext_data_expected_probe.sha256)
	rm -f "$tmp_actual"

	echo "expected_probe_sha256=$expected_hash"
	echo "actual_probe_sha256=$actual_hash"
	if [ "$actual_hash" != "$expected_hash" ]; then
		echo "Probe payload verification failed."
		exit 1
	fi
	echo "Probe payload verification passed."
}

function baremetal_datafs_suite_populate {
	baremetal_sys_check
	if [ ! -x "tools/ext23_fixture_suite.sh" ]; then
		echo "Missing tools/ext23_fixture_suite.sh or file is not executable"
		exit 1
	fi
	./tools/ext23_fixture_suite.sh populate
}

function baremetal_datafs_suite_verify {
	baremetal_sys_check
	if [ ! -x "tools/ext23_fixture_suite.sh" ]; then
		echo "Missing tools/ext23_fixture_suite.sh or file is not executable"
		exit 1
	fi
	./tools/ext23_fixture_suite.sh verify
}

function baremetal_datafs_ls {
	baremetal_sys_check
	if [ ! -x "tools/ext23_datafs_cli.sh" ]; then
		echo "Missing tools/ext23_datafs_cli.sh or file is not executable"
		exit 1
	fi
	./tools/ext23_datafs_cli.sh ls "${1:-/}"
}

function baremetal_datafs_read {
	baremetal_sys_check
	if [ ! -x "tools/ext23_datafs_cli.sh" ]; then
		echo "Missing tools/ext23_datafs_cli.sh or file is not executable"
		exit 1
	fi
	./tools/ext23_datafs_cli.sh read "$1"
}

function baremetal_datafs_write {
	baremetal_sys_check
	if [ ! -x "tools/ext23_datafs_cli.sh" ]; then
		echo "Missing tools/ext23_datafs_cli.sh or file is not executable"
		exit 1
	fi
	./tools/ext23_datafs_cli.sh write "$1" "$2"
}

function baremetal_datafs_mkdir {
	baremetal_sys_check
	if [ ! -x "tools/ext23_datafs_cli.sh" ]; then
		echo "Missing tools/ext23_datafs_cli.sh or file is not executable"
		exit 1
	fi
	./tools/ext23_datafs_cli.sh mkdir "$1"
}

function baremetal_ext23_scaffold {
	baremetal_src_check
	if [ ! -x "tools/ext23_kernel_scaffold.sh" ]; then
		echo "Missing tools/ext23_kernel_scaffold.sh"
		exit 1
	fi
	./tools/ext23_kernel_scaffold.sh --repo src/BareMetal
}

function baremetal_ext23_emu_test {
	baremetal_src_check
	baremetal_sys_check
	if [ ! -x "tools/ext23_emulator_smoke.sh" ]; then
		echo "Missing tools/ext23_emulator_smoke.sh"
		exit 1
	fi
	./tools/ext23_emulator_smoke.sh
}

function baremetal_ext23_crash_test {
	baremetal_sys_check
	if [ ! -x "tools/ext23_crash_test.sh" ]; then
		echo "Missing tools/ext23_crash_test.sh or file is not executable"
		exit 1
	fi
	./tools/ext23_crash_test.sh
}

function baremetal_ext23_sprint1_check {
	baremetal_sys_check
	if [ ! -x "tools/ext23_sprint1_check.sh" ]; then
		echo "Missing tools/ext23_sprint1_check.sh or file is not executable"
		exit 1
	fi
	./tools/ext23_sprint1_check.sh
}

function baremetal_ext23_sprint2_check {
	baremetal_sys_check
	if [ ! -x "tools/ext23_sprint2_check.sh" ]; then
		echo "Missing tools/ext23_sprint2_check.sh or file is not executable"
		exit 1
	fi
	./tools/ext23_sprint2_check.sh
}

function baremetal_ext23_live_test {
	baremetal_src_check
	baremetal_sys_check
	if [ ! -x "tools/ext23_live_io_test.sh" ]; then
		echo "Missing tools/ext23_live_io_test.sh or file is not executable"
		exit 1
	fi
	./tools/ext23_live_io_test.sh
}

function baremetal_app {
	baremetal_sys_check
	cd sys
	if [ -f $1 ]; then
		./bmfs bmfs.img format /force
		./bmfs bmfs.img write $1
		cat fat32.img bmfs.img > baremetal_os.img
		cd ..
	else
		echo "$1 does not exist."
		cd ..
	fi
}

function baremetal_help {
	echo "BareMetal-OS Script"
	echo "Available commands:"
	echo "clean    - Clean the src and bin folders"
	echo "setup    - Clean and setup"
	echo "update   - Pull in the latest code"
	echo "build    - Build source code"
	echo "install  - Install binary to disk image"
	echo "demos    - Install demos to disk image"
	echo "run      - Run the OS via QEMU"
	echo "run-uefi - Run the OS via QEMU in UEFI mode"
	echo "run-2    - Run a second instance of BareMetal for network testing"
	echo "datafs   - Create or refresh sys/ext_data.img for ext2/3 data tests"
	echo "datafs-info - Show ext filesystem metadata for sys/ext_data.img"
	echo "datafs-manifest - Show expected kernel data disk selection metadata"
	echo "datafs-populate - Seed ext_data.img with deterministic smoke-test files"
	echo "datafs-verify-probe - Verify /bmtest/smoke/probe.txt against expected hash"
	echo "datafs-suite-populate - Seed deterministic multi-file fixture suite and manifest"
	echo "datafs-suite-verify - Verify fixture suite files against the saved manifest"
	echo "datafs-ls [path] - Browse directory entries inside ext_data.img"
	echo "datafs-read <path> - Read a file from ext_data.img"
	echo "datafs-write <host-file> <path> - Write host file into ext_data.img"
	echo "datafs-mkdir <path> - Create a directory inside ext_data.img"
	echo "datafs-check - Run e2fsck (-fn) against ext_data.img"
	echo "datafs-replay-test - Run replay-oriented fsck flow on a copied ext_data image"
	echo "ext23-scaffold - Bootstrap fs/cache/vfs/ext2/layout/journal scaffolds in src/BareMetal"
	echo "ext23-emu-test - Run vertical milestone smoke flow (datafs+scaffold+build+qemu)"
	echo "ext23-crash-test - Run iterative crash/replay-oriented ext data image checks"
	echo "ext23-sprint1-check - Validate Sprint-1 gates (ext superblock + serial log hints)"
	echo "ext23-sprint2-check - Validate Sprint-2 read-path gates (probe payload + serial hints)"
	echo "ext23-live-test - Run bounded live boot and check mount/readdir/read/write serial markers"
	echo "vdi      - Generate VDI disk image for VirtualBox"
	echo "vmdk     - Generate VMDK disk image for VMware"
	echo "vpc      - Generate VPC disk image for HyperV"
	echo "bnr      - Build 'n Run"
	echo "bnr-uefi - Build 'n Run in UEFI mode"
	echo "*.app    - Install and run an app"
}

function baremetal_src_check {
	if [ ! -d src ]; then
		echo "Files are missing. Please run './baremetal.sh setup' first."
		exit 1
	fi
}

function baremetal_sys_check {
	if [ ! -d sys ]; then
		echo "Files are missing. Please run './baremetal.sh setup' first."
		exit 1
	fi
}

if [ $# -eq 0 ]; then
	baremetal_help
elif [ $# -eq 1 ]; then
	if [ "$1" == "setup" ]; then
		baremetal_setup
	elif [ "$1" == "clean" ]; then
		baremetal_clean
	elif [ "$1" == "build" ]; then
		baremetal_build
	elif [ "$1" == "install" ]; then
		baremetal_install
	elif [ "$1" == "update" ]; then
		baremetal_update
	elif [ "$1" == "help" ]; then
		baremetal_help
	elif [ "$1" == "run" ]; then
		baremetal_run
	elif [ "$1" == "run-uefi" ]; then
		baremetal_run-uefi
	elif [ "$1" == "run-2" ]; then
		baremetal_run_netclient
	elif [ "$1" == "datafs" ]; then
		baremetal_datafs
	elif [ "$1" == "datafs-info" ]; then
		baremetal_datafs_info
	elif [ "$1" == "datafs-manifest" ]; then
		baremetal_datafs_manifest
	elif [ "$1" == "datafs-populate" ]; then
		baremetal_datafs_populate
	elif [ "$1" == "datafs-verify-probe" ]; then
		baremetal_datafs_verify_probe
	elif [ "$1" == "datafs-suite-populate" ]; then
		baremetal_datafs_suite_populate
	elif [ "$1" == "datafs-suite-verify" ]; then
		baremetal_datafs_suite_verify
	elif [ "$1" == "datafs-ls" ]; then
		baremetal_datafs_ls
	elif [ "$1" == "datafs-check" ]; then
		baremetal_datafs_check
	elif [ "$1" == "datafs-replay-test" ]; then
		baremetal_datafs_replay_test
	elif [ "$1" == "ext23-scaffold" ]; then
		baremetal_ext23_scaffold
	elif [ "$1" == "ext23-emu-test" ]; then
		baremetal_ext23_emu_test
	elif [ "$1" == "ext23-crash-test" ]; then
		baremetal_ext23_crash_test
	elif [ "$1" == "ext23-sprint1-check" ]; then
		baremetal_ext23_sprint1_check
	elif [ "$1" == "ext23-sprint2-check" ]; then
		baremetal_ext23_sprint2_check
	elif [ "$1" == "ext23-live-test" ]; then
		baremetal_ext23_live_test
	elif [ "$1" == "demos" ]; then
		baremetal_install_demos
	elif [ "$1" == "vdi" ]; then
		baremetal_vdi
	elif [ "$1" == "vmdk" ]; then
		baremetal_vmdk
	elif [ "$1" == "vpc" ]; then
		baremetal_vpc
	elif [ "$1" == "bnr" ]; then
		baremetal_bnr
	elif [ "$1" == "bnr-uefi" ]; then
		baremetal_bnr-uefi
	elif [[ "$*" == *".app"* ]]; then
		baremetal_app $1
	else
		echo "Invalid argument '$1'"
	fi
elif [ $# -eq 2 ]; then
	if [ "$1" == "build" ]; then
		baremetal_build $2
	elif [ "$1" == "install" ]; then
		baremetal_install $2
	elif [ "$1" == "setup" ]; then
		baremetal_setup $2
	elif [ "$1" == "datafs-ls" ]; then
		baremetal_datafs_ls "$2"
	elif [ "$1" == "datafs-read" ]; then
		baremetal_datafs_read "$2"
	elif [ "$1" == "datafs-mkdir" ]; then
		baremetal_datafs_mkdir "$2"
	elif [ "$1" == "datafs-write" ]; then
		echo "Usage: bash ./baremetal.sh datafs-write <host-file> <ext-path>"
		exit 1
	fi
elif [ $# -eq 3 ]; then
	if [ "$1" == "datafs-write" ]; then
		baremetal_datafs_write "$2" "$3"
	fi
fi
