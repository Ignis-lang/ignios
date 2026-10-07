#!/usr/bin/env bash
# Boots QEMU headless, waits for the console prompt on COM1, types a fixed
# key sequence through the QEMU monitor, dumps the framebuffer and checks
# that the serial log carries the expected echo.
#
# Usage: scripts/keytest.sh <serial-log> <output.ppm> <timeout-seconds> -- <qemu command...>
#
# The QEMU command must log COM1 to <serial-log> and must not claim stdio:
# this script attaches the monitor there.

# Exit on any error, unset variable or failed pipeline stage.
set -euo pipefail

if [ "$#" -lt 5 ] || [ "$4" != "--" ]; then
  echo "usage: $0 <serial-log> <output.ppm> <timeout-seconds> -- <qemu command...>" >&2
  exit 2
fi

serial_log=$1
output=$2
timeout_seconds=$3
shift 4

prompt_pattern='^> '

# Covers Shift on digits and letters, a Backspace inside the line, two
# Backspaces at an empty prompt (which must not erase it), Enter and Caps
# Lock. The names are those of the QEMU monitor `sendkey` command. The script
# waits 0.2 s between keys to give the guest time to handle each one.
keys=(
  h i shift-1 spc backspace ret
  backspace backspace shift-a b c ret
  x y z caps_lock q caps_lock w
)

# What the serial transcript must show after the keyboard line, once every
# backspace is applied: `h i shift-1 spc backspace` leaves `hi!`, and Caps
# Lock is on only between the two `caps_lock` presses, so `q` is typed in
# upper case.
expected_lines='> hi!
> Abc
> xyzQw'

# Each erased character is mirrored as backspace, space, backspace.
expected_backspaces=2

# Polls the serial log until `pattern` appears or the timeout passes.
wait_for_serial() {
  local pattern=$1
  local deadline=$((SECONDS + timeout_seconds))

  until grep -q -- "$pattern" "$serial_log" 2>/dev/null; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "keytest: no '$pattern' in $serial_log after ${timeout_seconds}s" >&2
      return 1
    fi

    sleep 0.2
  done
}

# Produces the QEMU monitor script on stdout: wait for the prompt, type the
# keys, wait for the last echoed text, take a screendump and quit.
send_monitor_commands() {
  if ! wait_for_serial "$prompt_pattern"; then
    echo quit
    return 1
  fi

  local key

  for key in "${keys[@]}"; do
    echo "sendkey $key"
    sleep 0.2
  done

  wait_for_serial 'xyzQw' || true
  echo "screendump $output"
  sleep 1
  echo quit
}

rm -f "$serial_log" "$output"
send_monitor_commands | "$@" -monitor stdio >/dev/null

if [ ! -s "$output" ]; then
  echo "keytest: QEMU wrote no $output" >&2
  exit 1
fi

# Replays the serial log as a terminal would, where a backspace byte removes the
# previous character. The result must equal `expected_lines`, and the number of
# backspace bytes must match, which proves the console mirrors an erase as
# backspace, space, backspace.
python3 - "$serial_log" "$expected_lines" "$expected_backspaces" <<'PYTHON'
import sys

log_path, expected, expected_backspaces = sys.argv[1], sys.argv[2], int(sys.argv[3])
raw = open(log_path, "rb").read()

marker = b"keyboard: "
start = raw.find(marker)

if start < 0:
    sys.exit("keytest: no keyboard line in the serial log")

typed = raw[raw.index(b"\n", start) + 1:]
backspaces = typed.count(b"\x08")

screen = []

for byte in typed.replace(b"\r", b""):
    if byte == 0x08:
        if screen:
            screen.pop()
    else:
        screen.append(chr(byte))

transcript = "".join(screen)

print("keytest: echoed lines after backspaces:")
print(transcript)

if transcript != expected:
    sys.exit(f"keytest: expected {expected!r}, got {transcript!r}")

if backspaces != expected_backspaces:
    sys.exit(f"keytest: expected {expected_backspaces} backspace bytes, got {backspaces}")

print("keytest: ok")
PYTHON
