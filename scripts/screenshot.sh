#!/usr/bin/env bash
# Boots QEMU headless, waits until the serial log shows the console prompt,
# then dumps the framebuffer through the QEMU monitor and quits.
#
# Usage: scripts/screenshot.sh <serial-log> <output.ppm> <timeout-seconds> -- <qemu command...>
#
# The QEMU command must log COM1 to <serial-log> and must not claim stdio:
# this script attaches the monitor there.

# Exit on any error, unset variable or failed pipeline stage.
set -euo pipefail

if [ "$#" -lt 5 ] || [ "$4" != "--" ]; then
  echo "usage: $0 <serial-log> <output.ppm> <timeout-seconds> -- <qemu command...>" >&2
  exit 2
fi

# Arguments before `--`: serial log path, output image path, timeout. Everything
# after `--` is the QEMU command line.
serial_log=$1
output=$2
timeout_seconds=$3
shift 4

# The prompt is the last thing the kernel prints, at the start of a line.
prompt_pattern='^> '

# Produces the QEMU monitor script on stdout. The monitor reads it on its
# standard input (`-monitor stdio`): wait until the prompt shows up in the
# serial log, then `screendump` (framebuffer to a PPM file) and `quit`.
send_monitor_commands() {
  local deadline=$((SECONDS + timeout_seconds))

  until grep -q "$prompt_pattern" "$serial_log" 2>/dev/null; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "screenshot: no prompt in $serial_log after ${timeout_seconds}s" >&2
      echo quit
      return 1
    fi

    sleep 0.2
  done

  echo "screendump $output"
  sleep 1
  echo quit
}

# Start from a clean state so a stale log or image cannot satisfy the checks.
# The pipe feeds the monitor commands to QEMU, and the guest output goes to the
# serial log file, so QEMU's own stdout is discarded.
rm -f "$serial_log" "$output"
send_monitor_commands | "$@" -monitor stdio >/dev/null

if [ ! -s "$output" ]; then
  echo "screenshot: QEMU wrote no $output" >&2
  exit 1
fi
