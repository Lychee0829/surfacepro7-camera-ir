#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Load the IPU4P stack with the ISP's IOMMU group in identity mode.
#
# The IPU4 driver programs CPU physical addresses (virt_to_phys/page_to_phys)
# into the IPU MMU page tables. With the IOMMU translating DMA (the default on
# Ubuntu, Fedora and most distribution kernels), every ISP access to those
# addresses faults (DMAR "PTE Read access is not set"), the CSE cannot read the
# firmware and authentication fails ("FW authentication failed", "CSE
# boot_load failed").
#
# Switching only the ISP's IOMMU group to identity mode keeps translation on
# for every other device. The group type can only be changed while no driver
# is bound, so this must run before intel_ipu4 binds - blacklist intel_ipu4 so
# udev does not load it first, and run this script at boot instead.
#
#   sudo ./scripts/load-ipu4.sh

set -eu
DEV=0000:00:05.0
GRP=/sys/bus/pci/devices/$DEV/iommu_group

[ -e /sys/bus/pci/devices/$DEV ] || { echo "ISP $DEV not found"; exit 1; }
[ "$(cat /sys/bus/pci/devices/$DEV/device)" = 0x8a19 ] ||
	{ echo "$DEV is not an IPU4P (8086:8a19)"; exit 1; }

if [ -e /sys/bus/pci/devices/$DEV/driver ]; then
	echo "intel_ipu4 already bound; reboot to change the IOMMU group type"
	exit 1
fi

if [ -e "$GRP" ] && [ "$(cat "$GRP/type")" != identity ]; then
	# never relax DMA protection for anything but the ISP itself
	[ "$(ls "$GRP/devices")" = "$DEV" ] ||
		{ echo "IOMMU group of $DEV contains other devices, refusing"; exit 1; }
	echo identity > "$GRP/type"
fi
echo "IOMMU group: $(cat "$GRP/type" 2>/dev/null || echo none)"

modprobe intel_ipu4
modprobe surfacepro7_acpi
