# Ignis OS

An x86_64 UEFI kernel written in Ignis, booted by Limine.

## Build and run

The toolchain (clang, lld, Limine, QEMU, OVMF, mtools, netpbm, Python) comes
from the flake:

```sh
nix develop
make run            # boot in QEMU with the serial console on stdio
make run-headless   # boot without a display, log COM1 to build/serial.log
make screenshot     # boot headless and save the screen to build/screen.png
make keytest        # boot headless, type keys through the QEMU monitor,
                    # check the echo on COM1 and save build/screen.png
```

The kernel draws a text console on the framebuffer and mirrors everything it
prints there to COM1, so the serial log carries the same text as the screen.
After the banner it polls the PS/2 keyboard (scancode set 1, US layout, Shift
and Caps Lock) and echoes each line typed at the `>` prompt. Backspace stops at
the prompt, Enter starts a new prompt, and a line holds up to 128 characters.

The kernel needs an Ignis compiler with freestanding support. The Makefile
expects it at `../ignisc.rs/build/bootstrap/stage1/ignis`; point elsewhere with
`make IGNIS=/path/to/ignis`.

Targets: `kernel` (`build/kernel.elf`), `image` (`build/ignis-os.img`, a FAT
ESP with Limine and the kernel), `run`, `run-headless`, `screenshot`, `keytest`, `font`
(regenerates `kernel/src/font_8x16.S`), `clean`.

The console font is Spleen 8x16 under the BSD 2-Clause license, see
`THIRD_PARTY.md`.
