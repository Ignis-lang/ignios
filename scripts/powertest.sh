#!/usr/bin/env bash
# Boots QEMU headless without -no-reboot, types `reboot` at the prompt, waits
# for the machine to boot a second time, types `shutdown`, and checks that
# QEMU exits by itself: the kernel reset the machine and then powered it off
# through ACPI.
#
# Usage: scripts/powertest.sh <serial-log> <timeout-seconds> -- <qemu command...>
#
# The QEMU command must log COM1 to <serial-log>, must not claim stdio (this
# script attaches the monitor there) and must not pass -no-reboot, or the
# reset would end QEMU. Every wait has <timeout-seconds>; QEMU as a whole gets
# four times that.

# Exit on any error, unset variable or failed pipeline stage.
set -euo pipefail

if [ "$#" -lt 4 ] || [ "$3" != "--" ]; then
  echo "usage: $0 <serial-log> <timeout-seconds> -- <qemu command...>" >&2
  exit 2
fi

serial_log=$1
timeout_seconds=$2
shift 3

# Waits until <serial-log> has at least $2 lines that match $1.
wait_for_count() {
  local pattern=$1
  local wanted=$2
  local deadline=$((SECONDS + timeout_seconds))
  local count

  while true; do
    count=$(grep -c -- "$pattern" "$serial_log" 2>/dev/null) || count=0

    if [ "$count" -ge "$wanted" ]; then
      return 0
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "powertest: fewer than $wanted lines matching '$pattern' after ${timeout_seconds}s" >&2
      return 1
    fi

    sleep 0.2
  done
}

# Prints the monitor commands that type `word` and Enter.
type_word() {
  local word=$1
  local index

  for ((index = 0; index < ${#word}; index++)); do
    echo "sendkey ${word:index:1}"
    sleep 0.05
  done

  echo "sendkey ret"
}

# Feeds the monitor. It never sends `quit`: QEMU has to end on its own. If it
# does not, the outer timeout ends it and the check below fails.
send_monitor_commands() {
  wait_for_count '^> ' 1 || return 0
  type_word reboot
  wait_for_count 'IgniOS booting' 2 || return 0
  wait_for_count '^> ' 2 || return 0
  type_word shutdown
  wait_for_count 'power: shutting down' 1 || return 0
  sleep 5
}

rm -f "$serial_log"

set +e
send_monitor_commands | timeout $((timeout_seconds * 4)) "$@" -monitor stdio >/dev/null
codes=("${PIPESTATUS[@]}")
set -e

qemu_status=${codes[1]}

for line in 'power: rebooting' 'power: shutting down'; do
  if ! grep -q -- "$line" "$serial_log"; then
    echo "powertest: no '$line' in $serial_log" >&2
    exit 1
  fi
done

boots=$(grep -c 'IgniOS booting' "$serial_log") || boots=0

if [ "$boots" -ne 2 ]; then
  echo "powertest: expected 2 boots, saw $boots" >&2
  exit 1
fi

if [ "$qemu_status" -ne 0 ]; then
  echo "powertest: QEMU did not power off by itself (exit status $qemu_status, 124 is the timeout)" >&2
  exit 1
fi

echo "powertest: ok, reboot booted the machine again and shutdown powered it off"
