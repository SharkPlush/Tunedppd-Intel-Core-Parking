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

cleanup_fun() {
    if ! rmdir "/sys/fs/cgroup/parked-cores"; then
        printf 'Failed to remove /sys/fs/cgroup/parked-cores\n'
    fi
    if ! rmdir "/var/lock/intel-park"; then
        printf 'Failed to remove lock\n'
    fi
}

apply_park_fun() {
    case $POWER_STATE in
        power-saver)
            if ! printf '%s' "$P_CORES" > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
                return 1
            fi
            if ! printf 'isolated' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                return 1
            fi
            ;;
        *)
            # If BALANCED_P_CORES is 0 then P cores will not be used in balanced mode ->
            # If it is 1 then P cores will be used in balanced mode.
            if [ "$POWER_STATE" = "balanced" ] && [ "$BALANCED_P_CORES" = "0" ]; then
                if ! printf '%s' "$P_CORES" > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
                    return 1
                fi
                if ! printf 'isolated' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                    return 1
                fi
            else
                if ! printf 'member' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                    return 1
                fi
                if ! printf '%s' "$A_CORES" > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
                    return 1
                fi
            fi
            ;;
    esac
    return 0
}

# --- ENTRY POINT ---
if [ "$EUID" -ne 0 ]; then
    printf 'This script must be run as root.\n'
    exit 1
fi

if ! mkdir -p /var/lock/intel-park; then
    printf 'Another instance of intel-park.sh is already running.\n'
    exit 1
fi

# Check for supported CPU
if ! grep -q '^vendor_id\s*: GenuineIntel' /proc/cpuinfo; then
    printf 'Your CPU is not an Intel CPU.\n'
    rmdir "/var/lock/intel-park"
    exit 1
fi
CPU_GEN="$(awk -F': ' '/^model/ {print $2; exit}' /proc/cpuinfo)"
readonly CPU_GEN
case $CPU_GEN in
    151|154|183|186|191|170|172)
        printf 'Supported CPU found.\n'
        ;;
    *)
        printf 'Your CPU is not supported.\n'
        rmdir "/var/lock/intel-park"
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
        rmdir "/var/lock/intel-park"
        exit 2
        ;;
esac

# We don't ever park E and LPE cores so we don't need to find them individually.
# Parking E cores causes power inefficency and parking LPE cores is just not a good idea.
P_CORES="$(< /sys/devices/cpu_core/cpus)"
readonly P_CORES
A_CORES="$(< /sys/devices/system/cpu/present)"
readonly A_CORES

BUSCTL_OUT=""
POWER_STATE=""

# Allows us to actually enable core parking.
if ! printf '+cpuset' > /sys/fs/cgroup/cgroup.subtree_control; then
    printf 'Failed to add +cpuset to cgroup.subtree_control\n Is your kernel 6.7 or newer?\n'
    rmdir "/var/lock/intel-park"
    exit 1
fi
if ! mkdir -p '/sys/fs/cgroup/parked-cores'; then
    printf 'Failed to create /sys/fs/cgroup/parked-cores\n'
    rmdir "/var/lock/intel-park"
    exit 1
fi

# If the script exits allow all the cores.
trap -- 'cleanup_fun' EXIT

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
    # Because this is a listener and not polling extra battery won't be wasted.
    if ! BUSCTL_OUT="$(busctl --system wait org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.DBus.Properties PropertiesChanged)"; then
        printf "Failed to start busctl listener.\n"
        exit 1
    fi
    if ! grep -q "ActiveProfile" <<<"$BUSCTL_OUT"; then
        continue
    fi

    if ! POWER_STATE="$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile | grep -m1 -oE "power-saver|balanced|performance")"; then
        printf "Failed to capture power profile state.\n"
        exit 1
    fi

    if ! apply_park_fun; then
         printf "Failed to adjust parked CPU cores.\n"
         exit 1
    fi
done
