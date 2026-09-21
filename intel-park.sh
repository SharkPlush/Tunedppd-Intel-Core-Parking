#!/bin/bash
# Created by SharkPlush on GitHub
# https://github.com/SharkPlush
# Copyright 2026 SharkPlush
# Licensed under PolyForm Noncommercial License 1.0.0
# Full license: https://github.com/SharkPlush/Tunedppd-Intel-Core-Parking/blob/main/LICENSE
# Report any issues to github.com/SharkPlush/Tunedppd-Intel-Core-Parking/issues

# I left comments for anyone who is curious how this works.
# If you want to control how the balanced power mode works read the comments.

set -euo pipefail

# --- ENTRY POINT ---
if [ -e "/tmp/intel-park.lock" ]; then
    printf 'Another instance of intel-park.sh is already running.\n'
    exit 1
fi
touch "/tmp/intel-park.lock"

# Check for supported CPU
CPU_GEN="$(awk '/^model\t/{print $3;exit}' /proc/cpuinfo)"
readonly CPU_GEN
case $CPU_GEN in
    151|154|183|186|191|170|172)
        printf 'Supported CPU found.\n'
        ;;
    *)
        printf 'Your CPU is not supported.\n'
        rm "/tmp/intel-park.lock"
        exit 2
        ;;
esac

# Variable for controlling if the balanced power profile should have P cores utilized.
: "${BALANCED_P_CORES:=0}"
readonly BALANCED_P_CORES
case $BALANCED_P_CORES in
    0|1)
        ;;
    *)
        printf 'The BALANCED_P_CORES variable can only be 0 or 1.\n'
        rm "/tmp/intel-park.lock"
        exit 2
        ;;
esac

# We don't ever park E and LPE cores so we don't need to find them individually.
# Parking E cores causes power inefficency and parking LPE cores is just not a good idea.
LPE_CORES="16-17"
readonly LPE_CORES
P_CORES="0-8"
readonly P_CORES
E_CORES="8-15"
readonly E_CORES

BUSCTL_OUT=""
POWER_STATE=""

# Allows us to actually enable core parking.
if ! printf '+cpuset\n' > /sys/fs/cgroup/cgroup.subtree_control; then
    printf "Failed to add +cpuset to cgroup.subtree_control\n Is your kernel 6.7 or newer?\n"
    rm "/tmp/intel-park.lock"
    exit 1
fi
if ! mkdir -p '/sys/fs/cgroup/parked-cores'; then
    printf "Failed to create '/sys/fs/cgroup/parked-cores'\n"
    rm "/tmp/intel-park.lock"
    exit 1
fi

# If the script exits allow all the cores.
trap 'rm "/tmp/intel-park.lock"; rmdir "/sys/fs/cgroup/parked-cores"' EXIT


inotifywait -m -q -e modify /sys/bus/pci/devices/0000:00:04.0/workload_hint/workload_type_index | while read -r _; do
    HINT="$(< /sys/bus/pci/devices/0000:00:04.0/workload_hint/workload_type_index)"
    case $HINT in
        0)
            if ! printf '0-15' > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
                return 1
            fi
            if ! printf 'isolated' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                return 1
            fi
            printf 'IDLE PARK.\n'
            ;;
        1|2)
            if ! printf '0-7' > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
                return 1
            fi
            if ! printf 'isolated' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                return 1
            fi
            printf 'BATTERY PARK.\n'
            ;;
        *)
            if ! printf '0-17' > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
                return 1
            fi
            if ! printf 'member' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                return 1
            fi
            printf 'SUSTAINED/BURSTY PARK.\n'
            ;;
    esac
done








# Before the main loop we should know the current power state the device is in and apply for that.
if ! POWER_STATE="$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile | grep -m1 -oE "power-saver|balanced|performance")"; then
    printf 'Failed to capture power profile state when starting script.\n'
    exit 1
fi
if ! apply_park_fun; then
     printf 'Failed to adjust parked CPU cores.\n'
     exit 1
fi

while true; do
    # busctl listens for a power state changed.
    # Becauuse this is a listener and not polling extra battery won't be wasted.
    if ! BUSCTL_OUT="$(busctl --system wait org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.DBus.Properties PropertiesChanged)"; then
        printf "Failed to start busctl listener.\n"
        exit 1
    fi
    grep -q "ActiveProfile" <<<"$BUSCTL_OUT" || continue

    if ! POWER_STATE="$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile | grep -m1 -oE "power-saver|balanced|performance")"; then
        printf "Failed to capture power profile state.\n"
        exit 1
    fi

    if ! apply_park_fun; then
         printf "Failed to adjust parked CPU cores.\n"
         exit 1
    fi
done
