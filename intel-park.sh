#!/bin/bash
# Created by SharkPlush on GitHub
# https://github.com/SharkPlush
# Copyright 2026 SharkPlush
# Licensed under PolyForm Noncommercial License 1.0.0
# Full license: https://github.com/SharkPlush/Tunedppd-Intel-Core-Parking/blob/main/LICENSE
# Report any issues to github.com/SharkPlush/Tunedppd-Intel-Core-Parking/issues
set -euo pipefail

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
LPE_CORES="16-17"
readonly LPE_CORES
P_CORES="0-8"
readonly P_CORES
E_CORES="8-15"
readonly E_CORES

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
if ! printf '1' > /sys/bus/pci/devices/0000:00:04.0/workload_hint/workload_hint_enable; then
    prinf "Failed to enable workload hints.\n"
    exit 1
fi
if ! printf '100' > /sys/bus/pci/devices/0000:00:04.0/workload_hint/notification_delay_ms; then
    prinf "Failed to adjust workload hint delay.\n"
fi

# If the script exits allow all the cores.
trap 'rm "/tmp/intel-park.lock"; rmdir "/sys/fs/cgroup/parked-cores"' EXIT


inotifywait -m -q -e modify /sys/bus/pci/devices/0000:00:04.0/workload_hint/workload_type_index | while read -r _; do
    HINT="$(< /sys/bus/pci/devices/0000:00:04.0/workload_hint/workload_type_index)"
    case $HINT in
        0)
            # If idle park everything but LPE
            if ! printf '0-7' > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
                exit 1
            fi
            if ! printf 'isolated' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                exit 1
            fi
            printf 'IDLE PARK.\n'
            ;;
        *)
            # If sustained park P
            if ! printf '0-17' > /sys/fs/cgroup/parked-cores/cpuset.cpus; then
                exit 1
            fi
            if ! printf 'isolated' > /sys/fs/cgroup/parked-cores/cpuset.cpus.partition; then
                exit 1
            fi
            printf 'SUSTAINED/BATTERY PARK.\n'
            ;;
    esac
done
