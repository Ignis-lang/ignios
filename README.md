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
```

The kernel draws a text console on the framebuffer and mirrors everything it
prints there to COM1, so the serial log carries the same text as the screen.

The kernel needs an Ignis compiler with freestanding support. The Makefile
expects it at `../ignisc.rs/build/bootstrap/stage1/ignis`; point elsewhere with
`make IGNIS=/path/to/ignis`.

Targets: `kernel` (`build/kernel.elf`), `image` (`build/ignis-os.img`, a FAT
ESP with Limine and the kernel), `run`, `run-headless`, `screenshot`, `font`
(regenerates `kernel/src/font_8x16.S`), `clean`.

The console font is Spleen 8x16 under the BSD 2-Clause license, see
`THIRD_PARTY.md`.
