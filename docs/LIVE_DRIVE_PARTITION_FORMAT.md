# Walkthrough: Partition and Format a Drive on a Live System

> [!CAUTION]
> These commands can erase data. Double-check target device names before writing.

This guide assumes you are booted into a Linux live environment and want to prepare a physical drive for BareMetal OS testing.

## 0) Identify the target drive

List drives:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
```

Optional additional view:

```bash
sudo fdisk -l
```

Set your target disk (example only):

```bash
export DISK=/dev/sdX
```

Confirm it is correct:

```bash
echo "$DISK"
lsblk "$DISK"
```

## 1) Unmount anything on the target disk

```bash
sudo umount ${DISK}?* 2>/dev/null || true
```

## 2) Choose install method

### Method A (recommended): write the hybrid BareMetal image directly

If you already built `baremetal_os.img`, write it to the disk:

```bash
sudo dd if=baremetal_os.img of="$DISK" bs=4M conv=fsync status=progress
sudo sync
```

Verify partition table appears:

```bash
lsblk "$DISK"
```

This is the simplest and most reliable method for BIOS/UEFI boot testing.

### Method B: manual partition + format (UEFI-focused)

Use this when you specifically want manual partition control.

#### 2.1 Create a GPT label and partitions

Example layout:
- Partition 1: EFI System Partition (FAT32), 512 MiB
- Partition 2: Data partition (ext4), remaining space

```bash
sudo parted -s "$DISK" mklabel gpt
sudo parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
sudo parted -s "$DISK" set 1 esp on
sudo parted -s "$DISK" mkpart primary ext4 513MiB 100%
```

#### 2.2 Format partitions

```bash
sudo mkfs.vfat -F 32 ${DISK}1
sudo mkfs.ext4 -F ${DISK}2
```

#### 2.3 Mount and stage boot files

```bash
sudo mkdir -p /mnt/bm-esp /mnt/bm-data
sudo mount ${DISK}1 /mnt/bm-esp
sudo mount ${DISK}2 /mnt/bm-data
sudo mkdir -p /mnt/bm-esp/EFI/BOOT
```

Copy the UEFI bootloader binary:

```bash
sudo cp BOOTX64.EFI /mnt/bm-esp/EFI/BOOT/BOOTX64.EFI
sudo sync
```

(If you have additional runtime files/apps, copy them to `/mnt/bm-data`.)

#### 2.4 Cleanly unmount

```bash
sudo umount /mnt/bm-data
sudo umount /mnt/bm-esp
```

## 3) Post-write verification

```bash
lsblk -f "$DISK"
```

For Method B, quickly inspect the EFI tree:

```bash
sudo mount ${DISK}1 /mnt/bm-esp
find /mnt/bm-esp -maxdepth 3 -type f
sudo umount /mnt/bm-esp
```

## 4) Boot test checklist

- Disable secure boot (BareMetal binaries are unsigned).
- Ensure target disk is first in boot order or select it manually at boot menu.
- For UEFI manual method, verify `EFI/BOOT/BOOTX64.EFI` exists.

## 5) Recovery / wipe commands (optional)

If you need to wipe signatures and start over:

```bash
sudo wipefs -a "$DISK"
sudo sgdisk --zap-all "$DISK"
```

Then repeat from Step 0.
