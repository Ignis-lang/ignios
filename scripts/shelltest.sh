#!/usr/bin/env bash
# Boots QEMU headless, waits for the console prompt on COM1, types a fixed
# shell session through the QEMU monitor and checks that the serial log shows
# what `cat`, `ls`, `touch` and `mkdir` must print, their errors included.
#
# Usage: scripts/shelltest.sh <serial-log> <timeout-seconds> -- <qemu command...>
#
# The QEMU command must log COM1 to <serial-log> and must not claim stdio:
# this script attaches the monitor there. Each command is typed key by key
# with the monitor `sendkey` command, then the script waits for the next
# prompt before it types the following one, so a command never runs into the
# output of the one before.

# Exit on any error, unset variable or failed pipeline stage.
set -euo pipefail

if [ "$#" -lt 4 ] || [ "$3" != "--" ]; then
  echo "usage: $0 <serial-log> <timeout-seconds> -- <qemu command...>" >&2
  exit 2
fi

serial_log=$1
timeout_seconds=$2
shift 3

# The session. Lines without `run` run as programs from /bin; the `run`
# prefix still works.
commands=(
  "cat /etc/motd"
  "ls /"
  "ls /bin"
  "mkdir /tmp"
  "mkdir /tmp"
  "touch /tmp/a /tmp/b"
  "ls /tmp"
  "cat /tmp/a"
  "cat /nope /etc/motd"
  "cat /etc"
  "ls /nope"
  "touch /nope/a"
  "mkdir /etc/motd/x"
  "mkdir"
  "run ls /dev"
  "ls /etc/motd"
  "rm /tmp/a"
  "ls /tmp"
  "rm /tmp"
  "rmdir /tmp"
  "rm /tmp/b"
  "rmdir /tmp"
  "ls /"
  "pwd"
  "nope"
)

# What the serial log must show after the keyboard line. A line that starts
# with `> ` is the echo of a command and opens its block; the lines after it,
# up to the next prompt, are what the command printed. Each block must match
# exactly, line for line, as regular expressions, after the ELF loader's
# report (`elf: ...`) is dropped. `S` stands for the line the kernel prints
# when a program ends. Directories list in creation order: `/dev` comes after
# the initramfs, whose members tar wrote sorted by name.
expected='> cat /etc/motd
Welcome to IgniOS\.
S0
> ls /
bin
etc
dev
S0
> ls /bin
cat
fstest
hello
ls
mkdir
mmtest
nativetest
pwd
reboot
rm
rmdir
shutdown
touch
S0
> mkdir /tmp
S0
> mkdir /tmp
mkdir: cannot create directory '"'"'/tmp'"'"': File exists
S1
> touch /tmp/a /tmp/b
S0
> ls /tmp
a
b
S0
> cat /tmp/a
S0
> cat /nope /etc/motd
cat: /nope: No such file or directory
Welcome to IgniOS\.
S1
> cat /etc
cat: /etc: Is a directory
S1
> ls /nope
ls: cannot access '"'"'/nope'"'"': No such file or directory
S2
> touch /nope/a
touch: cannot touch '"'"'/nope/a'"'"': No such file or directory
S1
> mkdir /etc/motd/x
mkdir: cannot create directory '"'"'/etc/motd/x'"'"': Not a directory
S1
> mkdir
mkdir: missing operand
S1
> run ls /dev
console
S0
> ls /etc/motd
/etc/motd
S0
> rm /tmp/a
S0
> ls /tmp
b
S0
> rm /tmp
rm: cannot remove '"'"'/tmp'"'"': Is a directory
S1
> rmdir /tmp
rmdir: failed to remove '"'"'/tmp'"'"': Directory not empty
S1
> rm /tmp/b
S0
> rmdir /tmp
S0
> ls /
bin
etc
dev
S0
> pwd
/
S0
> nope
run: /bin/nope: no such file or directory'

# Waits until <serial-log> has at least $1 lines that start with the prompt.
wait_for_prompts() {
  local wanted=$1
  local deadline=$((SECONDS + timeout_seconds))
  local count

  while true; do
    count=$(grep -c '^> ' "$serial_log" 2>/dev/null) || count=0

    if [ "$count" -ge "$wanted" ]; then
      return 0
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "shelltest: fewer than $wanted prompts in $serial_log after ${timeout_seconds}s" >&2
      return 1
    fi

    sleep 0.2
  done
}

# Prints the monitor `sendkey` names that type one line, then Enter.
keys_for() {
  local line=$1
  local index character

  for ((index = 0; index < ${#line}; index++)); do
    character=${line:index:1}

    case "$character" in
      [a-z0-9]) echo "$character" ;;
      " ") echo spc ;;
      "/") echo slash ;;
      ".") echo dot ;;
      "-") echo minus ;;
      *) echo "shelltest: no key for '$character'" >&2; exit 2 ;;
    esac
  done

  echo ret
}

# Feeds the monitor: waits for each prompt, types the next command.
send_monitor_commands() {
  local prompts=1
  local command key

  for command in "${commands[@]}"; do
    if ! wait_for_prompts "$prompts"; then
      echo quit
      return 1
    fi

    for key in $(keys_for "$command"); do
      echo "sendkey $key"
      sleep 0.05
    done

    prompts=$((prompts + 1))
  done

  wait_for_prompts "$prompts" || true
  echo quit
}

rm -f "$serial_log"

send_monitor_commands | "$@" -monitor stdio >/dev/null

EXPECTED="$expected" python3 -I - "$serial_log" <<'PYTHON'
import os
import re
import sys

raw = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
marker = "keyboard: PS/2"
start = raw.find(marker)

if start < 0:
    sys.exit("shelltest: no keyboard line in the serial log")

lines = [line.rstrip("\r") for line in raw[start:].split("\n")[1:]]
lines = [line for line in lines if not line.startswith("elf: ")]


def blocks(source):
    """Splits lines into blocks that each start with a `> ` command line."""
    result = []

    for line in source:
        if line.startswith("> "):
            result.append([line])
        elif result:
            result[-1].append(line)

    return result


def pattern(entry):
    if entry.startswith("S") and entry[1:].isdigit():
        return r"process \d+ exited with status " + entry[1:]

    return entry


wanted = blocks(os.environ["EXPECTED"].split("\n"))
actual = [block for block in blocks(lines) if block != ["> "]]
checked = 0

for index, block in enumerate(wanted):
    if index >= len(actual):
        sys.exit(f"shelltest: no output for {block[0]!r}")

    got = actual[index]

    if got[0] != block[0]:
        sys.exit(f"shelltest: expected the command {block[0]!r}, got {got[0]!r}")

    if len(got) != len(block) or not all(re.fullmatch(pattern(want), line) for want, line in zip(block, got)):
        print("\n".join(got))
        sys.exit(f"shelltest: {block[0]!r} printed {got[1:]!r}, expected {block[1:]!r}")

    checked += len(block)

print(f"shelltest: ok, {len(wanted)} commands, {checked} lines matched exactly")
PYTHON
