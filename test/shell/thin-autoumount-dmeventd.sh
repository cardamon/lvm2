#!/bin/bash
# Copyright (C) 2012-2016 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing to use,
# modify, copy, or redistribute it subject to the terms and conditions
# of the GNU General Public License v.2.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

# no automatic extensions, just umount

SKIP_WITH_LVMLOCKD=1
SKIP_WITH_LVMPOLLD=1

export LVM_TEST_THIN_REPAIR_CMD=${LVM_TEST_THIN_REPAIR_CMD-/bin/false}

is_lv_opened_()
{
	test $(get lv_field "$1" lv_device_open --binary) = "1"
}

. lib/inittest

#
# Main
#
which mkfs.ext2 || skip

aux have_thin 1 0 0 || skip

aux prepare_dmeventd

# Use autoextend percent 0 - so extension fails and triggers umount...
aux lvmconf "activation/thin_pool_autoextend_percent = 0" \
            "activation/thin_pool_autoextend_threshold = 70"

aux prepare_vg 2

mntdir="${PREFIX}mnt with space"
mntusedir="${PREFIX}mntuse"

lvcreate -L8M -V8M -n $lv1 -T $vg/pool
lvcreate -V8M -n $lv2 -T $vg/pool

mkfs.ext2 "$DM_DEV_DIR/$vg/$lv1"
mkfs.ext2 "$DM_DEV_DIR/$vg/$lv2"

lvchange --monitor y $vg/pool

mkdir "$mntdir" "$mntusedir"
mount "$DM_DEV_DIR/mapper/$vg-$lv1" "$mntdir"
mount "$DM_DEV_DIR/mapper/$vg-$lv2" "$mntusedir"

# Check both LVs are opened (~mounted)
is_lv_opened_ "$vg/$lv1"
is_lv_opened_ "$vg/$lv2"

touch "$mntusedir/file$$"
sync

# Running 'keeper' process sleep holds the block device still in use
sleep 60 < "$mntusedir/file$$" &
PID_SLEEP=$!

# Fill pool above 70%
dd if=/dev/zero of="$mntdir/file$$" bs=1M count=6 conv=fdatasync
lvs -a $vg

# Could loop here for a few secs so dmeventd can do some work
# In the worst case check only happens every 10 seconds :(
# With low water mark it should react way faster
for i in $(seq 1 12) ; do
	is_lv_opened_ "$vg/$lv1" || break
	test $i -lt 12 || die "$mntdir should have been unmounted by dmeventd!"
	sleep 1
done

is_lv_opened_ "$vg/$lv2" || \
	die "$mntusedir is not mounted here (sleep already expired??)"

# Kill device holding process
kill $PID_SLEEP
wait

is_lv_opened_ "$vg/$lv2" && {
	mount
	die "$mntusedir should have been unmounted by dmeventd!"
}

vgremove -f $vg

