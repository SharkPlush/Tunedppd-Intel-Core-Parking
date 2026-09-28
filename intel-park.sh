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
    (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] cleanup_fun started.\n' >&2

    (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Writing member into /sys/fs/cgroup/parked-cores/cpuset.cpus.partition\n' >&2
    if ! printf 'member' > '/sys/fs/cgroup/parked-cores/cpuset.cpus.partition'; then
        printf 'Failed to write member to cpuset.cpus.partition\n' >&2
    fi
    (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Wrote member into /sys/fs/cgroup/parked-cores/cpuset.cpus.partition\n' >&2

    (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Writing $P_CORES into /sys/fs/cgroup/parked-cores/cpuset.cpus\n" >&2
    if ! printf '%s' "$A_CORES" > '/sys/fs/cgroup/parked-cores/cpuset.cpus'; then
        printf 'Failed to add all cores to cpuset.cpus\n' >&2
    fi
    (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Wrote $A_CORES into /sys/fs/cgroup/parked-cores/cpuset.cpus\n" >&2

    (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Removing /sys/fs/cgroup/parked-cores\n" >&2
    if ! rmdir '/sys/fs/cgroup/parked-cores'; then
        printf 'Failed to remove /sys/fs/cgroup/parked-cores\n' >&2
    fi
    (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Removed /sys/fs/cgroup/parked-cores\n" >&2

    (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Removing lock file in /var/lock/intel-park\n" >&2
    if ! rmdir '/var/lock/intel-park'; then
        printf 'Failed to remove lock\n' >&2
    fi
    (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Removed locked file in /var/lock/intel-park\n" >&2
}

apply_park_fun() {
    (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] apply_park_fun started.\n' >&2
    (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Checking $POWER_STATE for core parking.\n' >&2
    case "$POWER_STATE" in
        power-saver)
            (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Adjusting core parking for power-saver.\n' >&2

            (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Writing $P_CORES into /sys/fs/cgroup/parked-cores/cpuset.cpus\n" >&2
            if ! printf '%s' "$P_CORES" > '/sys/fs/cgroup/parked-cores/cpuset.cpus'; then
                return 1
            fi
            (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Wrote $P_CORES into /sys/fs/cgroup/parked-cores/cpuset.cpus\n" >&2

            (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Writing isolated into /sys/fs/cgroup/parked-cores/cpuset.cpus.partition\n' >&2
            if ! printf 'isolated' > '/sys/fs/cgroup/parked-cores/cpuset.cpus.partition'; then
                return 1
            fi
            (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Wrote isolated into /sys/fs/cgroup/parked-cores/cpuset.cpus.partition\n' >&2
            (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] P cores parked.\n' >&2
            ;;
        *)
            # If BALANCED_P_CORES is 0 then P cores will not be used in balanced mode ->
            # If it is 1 then P cores will be used in balanced mode.
            if [[ "$POWER_STATE" = 'balanced' && "$BALANCED_P_CORES" = '0' ]]; then
                (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Adjusting core parking for balanced with P core parking.\n' >&2

                (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Writing $P_CORES into /sys/fs/cgroup/parked-cores/cpuset.cpus\n" >&2
                if ! printf '%s' "$P_CORES" > '/sys/fs/cgroup/parked-cores/cpuset.cpus'; then
                    return 1
                fi
                (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Wrote $P_CORES into /sys/fs/cgroup/parked-cores/cpuset.cpus\n" >&2

                (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Writing isolated into /sys/fs/cgroup/parked-cores/cpuset.cpus.partition\n' >&2
                if ! printf 'isolated' > '/sys/fs/cgroup/parked-cores/cpuset.cpus.partition'; then
                    return 1
                fi
                (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Wrote isolated into /sys/fs/cgroup/parked-cores/cpuset.cpus.partition\n' >&2
                (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] P cores parked.\n' >&2
            else
                (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Adjusting core parking for balanced without P core parking or performance.\n' >&2

                (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Writing member into /sys/fs/cgroup/parked-cores/cpuset.cpus.partition\n' >&2
                if ! printf 'member' > '/sys/fs/cgroup/parked-cores/cpuset.cpus.partition'; then
                    return 1
                fi
                (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Wrote member into /sys/fs/cgroup/parked-cores/cpuset.cpus.partition\n' >&2

                (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Writing $A_CORES into /sys/fs/cgroup/parked-cores/cpuset.cpus\n" >&2
                if ! printf '%s' "$A_CORES" > '/sys/fs/cgroup/parked-cores/cpuset.cpus'; then
                    return 1
                fi
                (( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Wrote $A_CORES into /sys/fs/cgroup/parked-cores/cpuset.cpus\n" >&2
                (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] P cores unparked.\n' >&2
            fi
            ;;
    esac
    return 0
}

# --- ENTRY POINT ---

: "${DEBUG:=0}"
readonly DEBUG

(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Checking for root privilages.\n' >&2
if [ "$EUID" -ne 0 ]; then
    printf 'This script must be run as root.\n' >&2
    exit 3
fi
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Script is running as root.\n' >&2

(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Checking for lock file in /var/lock/intel-park\n' >&2
if ! mkdir '/var/lock/intel-park' 2>/dev/null; then
    printf 'Another instance of intel-park.sh is already running.\n' >&2
    exit 1
fi
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Lock file created in /var/lock/intel-park\n' >&2

# Check for supported CPU

(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Checking CPU model in /proc/cpuinfo\n' >&2
case "$(< /proc/cpuinfo)" in
    *GenuineIntel*model*:*170*|*GenuineIntel*model*:*151*|*GenuineIntel*model*:*154*|*GenuineIntel*model*:*183*|*GenuineIntel*model*:*186*|*GenuineIntel*model*:*191*|*GenuineIntel*model*:*172*)
        ;;
    *)
        printf 'Your CPU is not supported.\n' >&2
        rmdir '/var/lock/intel-park'
        exit 4
esac
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Found a compatible CPU model.\n' >&2

# Variable for controlling if the balanced power profile should have P cores utilized.
: "${BALANCED_P_CORES:=0}"
readonly BALANCED_P_CORES
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Checking BALACED_P_CORES variable.\n' >&2
case "$BALANCED_P_CORES" in
    0|1)
        ;;
    *)
        printf 'The BALANCED_P_CORES variable can only be 0 or 1.\n' >&2
        rmdir '/var/lock/intel-park'
        exit 2
        ;;
esac
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] BALANCED_P_CORES variable is set.\n' >&2

# We don't ever park E and LPE cores so we don't need to find them individually.
# Parking E cores causes power inefficency and parking LPE cores is just not a good idea.
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Finding P cores in /sys/devices/cpu_cores/cpus\n' >&2
if ! P_CORES="$(< /sys/devices/cpu_core/cpus)"; then
    printf 'Could not find system P cores.\n'
    exit 4
fi
readonly P_CORES
(( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Found $P_CORES P cores.\n" >&2

(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Finding all system cores in /sys/devices/system/cpu/present\n' >&2
if ! A_CORES="$(< /sys/devices/system/cpu/present)"; then
    printf 'Could not find system all cores.\n'
    exit 4
fi
readonly A_CORES
(( DEBUG )) && printf "DEBUG: [%(%H:%M:%S)T] Found $A_CORES system cores.\n" >&2

BUSCTL_OUT=""
POWER_STATE=""
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] BUSCTL_OUT and POWER_STATE variables set.\n' >&2

# Allows us to actually enable core parking.
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Writing +cpuset to /sys/fs/cgroup/cgroup.subtree_control\n' >&2
if ! printf '+cpuset' > '/sys/fs/cgroup/cgroup.subtree_control'; then
    printf 'Failed to add +cpuset to cgroup.subtree_control\n Is your kernel 6.7 or newer?\n' >&2
    rmdir '/var/lock/intel-park'
    exit 4
fi
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Wrote +cpuset to /sys/fs/cgroup/cgroup.subtree_control\n' >&2

(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Making a /sys/fs/cgroup/parked-cores directory.\n' >&2
if ! mkdir -p '/sys/fs/cgroup/parked-cores'; then
    printf 'Failed to create /sys/fs/cgroup/parked-cores\n' >&2
    rmdir '/var/lock/intel-park'
    exit 4
fi
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] /sys/fs/cgroup/parked-cores directory has been made.\n' >&2


# If the script exits allow all the cores.
trap -- cleanup_fun EXIT
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Trap has been passed.\n' >&2

# Before the main loop we should know the current power state the device is in and apply for that.
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Checking current power profile state.\n' >&2
case "$(busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile)" in
    *power-saver*)
        (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Current power profile is power-saver.\n' >&2
        POWER_STATE='power-saver'
        (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Setting POWER_STATE to power-saver\n' >&2
        ;;
    *balanced*)
        (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Current power profile is balanced.\n' >&2
        POWER_STATE='balanced'
        (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Setting POWER_STATE to balanced\n' >&2
        ;;
    *performance*)
        (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Current power profile is performance.\n' >&2
        POWER_STATE='performance'
        (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Setting POWER_STATE to performance\n' >&2
        ;;
    *)
        printf 'Failed to capture power profile state when starting script.\n' >&2
        exit 1
        ;;
esac
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Current power profile state captured.\n' >&2

(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Adjusting the core parking for current power profile.\n' >&2
if ! apply_park_fun; then
     printf 'Failed to adjust parked CPU cores.\n' >&2
     exit 4
fi
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Parked CPU cores have been adjusted.\n' >&2

# busctl listens for a power state changed.
# Because this is a listener and not polling extra battery won't be wasted.
(( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Starting main loop.\n' >&2
while read -r BUSCTL_OUT; do
    case "$BUSCTL_OUT" in
        *power-saver*)
            (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Current power profile is power-saver.\n' >&2
            POWER_STATE='power-saver'
            (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Setting POWER_STATE to power-saver\n' >&2
            ;;
        *balanced*)
            (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Current power profile is balanced.\n' >&2
            POWER_STATE='balanced'
            (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Setting POWER_STATE to balanced\n' >&2
            ;;
        *performance*)
            (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Current power profile is performance.\n' >&2
            POWER_STATE='performance'
            (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Setting POWER_STATE to performance\n' >&2
            ;;
        *)
            (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Busctl noise that causes main loop restart.\n' >&2
            continue
            ;;
    esac
    (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Adjusting the core parking for current power profile.\n' >&2
    if ! apply_park_fun; then
         printf 'Failed to adjust parked CPU cores.\n' >&2
         exit 4
    fi
    (( DEBUG )) && printf 'DEBUG: [%(%H:%M:%S)T] Parked CPU cores have been adjusted.\n' >&2
done < <(busctl --system monitor --match "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/freedesktop/UPower/PowerProfiles'" 2>/dev/null)
printf 'Failed to start busctl monitor.\n' >&2
exit 1
