#!/system/bin/sh

set -e

MODDIR=${0%/*}
if [ "$ZYGISK_ENABLED" ]; then
  exit 0
fi

cd "$MODDIR"

if [ "$(which magisk)" ]; then
  for file in ../*; do
    if [ -d "$file" ] && [ -d "$file/zygisk" ] && ! [ -f "$file/disable" ]; then
      if [ -f "$file/post-fs-data.sh" ]; then
        cd "$file"
        log -p i -t "zygisk-sh" "Manually trigger post-fs-data.sh for $file"

        # INFO: Don't propagate errexit
        set +e

        sh "$(realpath ./post-fs-data.sh)"

        # INFO: Re-enable errexit
        set -e

        cd "$MODDIR"
      fi
    fi
  done
fi

create_sys_perm() {
  mkdir -p $1
  chmod 555 $1
  chcon u:object_r:system_file:s0 $1
}

export TMP_PATH=/data/adb/rezygisk

# INFO: Do NOT wipe the whole directory on every boot.
#
#   A soft reboot (setprop ctl.restart zygote / ksud's emulated soft reboot)
#   re-runs this script while the monitor from the previous boot is still alive
#   and still tracing init. Wiping TMP_PATH removed its control socket and its
#   state file out from under it, and the fresh monitor then failed to bind -
#   Zygisk stayed dead until a full reboot.
#
#   Only remove what must not survive: the previous state.json, so the dashboard
#   never reports stale data from an earlier boot. The socket is left alone; a
#   live monitor keeps it, and a dead one leaves a stale file that bind() will
#   simply replace after the monitor unlinks it at startup.
rm -f "$TMP_PATH/state.json"

mkdir -p "$TMP_PATH"
create_sys_perm $TMP_PATH

# INFO: We need to cleanup the module.prop to its default state before ReZygisk writes to it
#         so that it never duplicates the module status in there.
# INFO: Guarded, as under errexit a missing backup would prevent the monitor from starting.
if [ -f "$MODDIR/module.prop.bak" ]; then
  cp "$MODDIR/module.prop.bak" "$MODDIR/module.prop"
fi

# INFO: Utilize the one with the biggest output, as some devices with Tango have the full list
#         in ro.product.cpu.abilist but others only have a subset there, and the full list in
#         ro.system.product.cpu.abilist
CPU_ABIS_PROP1=$(getprop ro.system.product.cpu.abilist)
CPU_ABIS_PROP2=$(getprop ro.product.cpu.abilist)

if [ "${#CPU_ABIS_PROP2}" -gt "${#CPU_ABIS_PROP1}" ]; then
  CPU_ABIS=$CPU_ABIS_PROP2
else
  CPU_ABIS=$CPU_ABIS_PROP1
fi

if [[ "$CPU_ABIS" == *"arm64-v8a"* || "$CPU_ABIS" == *"x86_64"* ]]; then
  ./bin/zygisk-ptrace64 monitor &
else
  # INFO: Device is 32-bit only

  ./bin/zygisk-ptrace32 monitor &
fi

exit 0
