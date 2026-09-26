#!/usr/bin/env bash
# Created by SharkPlush on GitHub
# https://github.com/SharkPlush
# Copyright 2026 SharkPlush
# Licensed under PolyForm Noncommercial License 1.0.0
# Full license: https://github.com/SharkPlush/Tunedppd-Intel-Core-Parking/blob/main/LICENSE
# Report any issues to https://github.com/SharkPlush/Tunedppd-Intel-Core-Parking/issues

# I left comments for anyone who is curious how this works.
# If you want to control how the balanced power mode works read the comments.

# TODO:
# Add debugging.
# Add --help

set -euo pipefail

cleanup_fun() {
    if ! rmdir "/sys/fs/cgroup/parked-cores"; then
        printf 'Failed to remove /sys/fs/cgroup/parked-cores\n' >&2
    fi
    if ! rmdir "/var/lock/intel-park"; then
        printf 'Failed to remove lock\n' >&2
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
            if [[ "$POWER_STATE" = "balanced" && "$BALANCED_P_CORES" = "0" ]]; then
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
    printf 'This script must be run as root.\n' >&2
    exit 1
fi

if ! mkdir "/var/lock/intel-park" 2>/dev/null; then
    printf 'Another instance of intel-park.sh is already running.\n' >&2
    exit 1
fi

# Check for supported CPU
if [[ "$(< /proc/cpuinfo)" != *GenuineIntel* ]]; then
    printf 'Your CPU is not an Intel CPU.\n' >&2
    rmdir "/var/lock/intel-park"
    exit 2
fi
case $(< /proc/cpuinfo) in
    *$'\n'model*:*151*|*$'\n'model*:*154*|*$'\n'model*:*183*|*$'\n'model*:*186*|*$'\n'model*:*191*|*$'\n'model*:*170*|*$'\n'model*:*172*)
        ;;
    *)
        printf 'Your CPU is not supported.\n' >&2
        rmdir "/var/lock/intel-park"
        exit 2
esac

# Variable for controlling if the balanced power profile should have P cores utilized.
: "${BALANCED_P_CORES:=0}"
readonly BALANCED_P_CORES
case $BALANCED_P_CORES in
    0|1)
        ;;
    *)
        printf 'The BALANCED_P_CORES variable can only be 0 or 1.\n' >&2
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
    printf 'Failed to add +cpuset to cgroup.subtree_control\n Is your kernel 6.7 or newer?\n' >&2
    rmdir "/var/lock/intel-park"
    exit 1
fi
if ! mkdir -p '/sys/fs/cgroup/parked-cores'; then
    printf 'Failed to create /sys/fs/cgroup/parked-cores\n' >&2
    rmdir "/var/lock/intel-park"
    exit 1
fi

# If the script exits allow all the cores.
trap -- 'cleanup_fun' EXIT

# Before the main loop we should know the current power state the device is in and apply for that.
case $(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile) in
    *power-saver*)
        POWER_STATE="power-saver"
        ;;
    *balanced*)
        POWER_STATE="balanced"
        ;;
    *performance*)
        POWER_STATE="performance"
        ;;
    *)
        printf 'Failed to capture power profile state when starting script.\n' >&2
        exit 1
        ;;
esac
if ! apply_park_fun; then
     printf 'Failed to adjust parked CPU cores.\n' >&2
     exit 1
fi

# busctl listens for a power state changed.
# Because this is a listener and not polling extra battery won't be wasted.
while read -r BUSCTL_OUT; do
    case $BUSCTL_OUT in
        *power-saver*)
            POWER_STATE="power-saver"
            ;;
        *balanced*)
            POWER_STATE="balanced"
            ;;
        *performance*)
            POWER_STATE="performance"
            ;;
        *)
            continue
            ;;
    esac
    if ! apply_park_fun; then
        printf 'Failed to adjust parked CPU cores.\n' >&2
        exit 1
    fi
done < <(busctl --system monitor --match "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/freedesktop/UPower/PowerProfiles'" 2>/dev/null)
printf 'Failed to start busctl monitor.\n' >&2
exit 1
