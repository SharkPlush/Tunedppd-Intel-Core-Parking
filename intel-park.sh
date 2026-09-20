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

# We don't ever park E and LPE cores so we don't need to find them individually.
# Parking E cores causes power inefficency and parking LPE cores is just not a good idea.
P_CORES="$(< /sys/devices/cpu_core/cpus)"
readonly P_CORES
A_CORES="$(< /sys/devices/system/cpu/present)"
readonly A_CORES

HINT=""

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
trap 'rmdir "/sys/fs/cgroup/parked-cores"' EXIT

# Before the main loop we should know the current power state the device is in and apply for that.
if ! HINT="$(< /sys/bus/pci/devices/0000:00:04.0/workload_hint/workload_type_index)"; then
    printf 'Failed to capture power profile state when starting script.\n'
    exit 1
fi

inotifywait -m -q -e modify /sys/bus/pci/devices/0000:00:04.0/workload_hint/workload_type_index | while read -r _; do
    HINT="$(< /sys/bus/pci/devices/0000:00:04.0/workload_hint/workload_type_index)"
    case $HINT in
        0)
            if ! printf '%s' "$P_CORES" > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
                exit 1
            fi
            if ! printf '%s' "$P_CORES" > /sys/fs/cgroup/parked-cores/cpuset.cpus.exclusive; then
                exit 1
            fi
            if ! printf 'isolated' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                exit 1
            fi
            printf 'idle-ps-test.\n'
            ;;
        1|2)
            if ! printf '%s' "$P_CORES" > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
                exit 1
            fi
            if ! printf '%s' "$P_CORES" > /sys/fs/cgroup/parked-cores/cpuset.cpus.exclusive; then
                exit 1
            fi
            if ! printf 'isolated' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                exit 1
            fi
            printf 'active-ps-test.\n'
            ;;
        3)
            if ! printf 'member' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                exit 1
            fi
            printf 'sustained-ld-test.\n'
            ;;
        *)
            if ! printf 'member' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                exit 1
            fi
            printf 'performance-ld-test.\n'
            ;;
    esac
done
