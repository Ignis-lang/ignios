# IgniOS

A Unix-like x86_64 kernel written in [Ignis](https://github.com/Ignis-lang/ignis), booted by Limine on UEFI.

IgniOS is the first large Ignis program that lives outside the compiler. It doubles as a test bench: when the kernel hits a compiler bug, the bug is fixed in the compiler rather than worked around here. Volatile access, freestanding builds, C-layout records, C function pointers and Intel-syntax inline asm all landed in Ignis because this kernel needed them.

![IgniOS console after typing a few lines](docs/screenshot.png)

## Status

Early, and only tested in QEMU with OVMF.

| Area | State |
|---|---|
| Boot | Limine (base revision 6) on UEFI, higher-half ELF at `0xffffffff80000000` |
| Console | Framebuffer text console, Spleen 8x16 font, 16 ANSI colors, cursor, scrolling; mirrored to COM1 |
| CPU | Own GDT and TSS (IST stack for double faults), IDT with exception reports |
| Interrupts | ACPI MADT parsed; keyboard routed through the IOAPIC to vector 0x21 with local APIC end of interrupt; 8259 remapped to 0x20-0x2F and fully masked; idle loop sleeps with `sti; hlt` |
| Timer | Local APIC timer calibrated against PIT channel 2, periodic 100 Hz tick on vector 0x30; `uptime` at the prompt prints the time since boot |
| Threads | Kernel threads with their own stacks and a guard page, a round-robin run queue, `yield`, `sleep` and `exit`, an idle thread, and preemption by the timer tick with 100 ms time slices; `ps` lists the threads and `threads` starts a demo; the boot thread runs the terminal |
| Input | PS/2 keyboard, scancode set 1, US layout, Shift and Caps Lock, line editing at a `>` prompt |
| Memory | Bitmap frame allocator over the Limine memory map; own 4-level page tables (kernel image per segment with W^X, direct map with 2 MiB pages, write-combining framebuffer, NX and write protection on); kernel heap in the higher half behind the compiler's allocation handlers |
| User mode | Per-process address spaces (own PML4, shared kernel half, U/S pages, frames freed on exit); ring 3 entered with `iretq`, left through `SYSCALL`/`SYSRET` or an interrupt (TSS.RSP0 follows the running thread); a Linux x86_64 syscall subset (`write`, `exit`, `exit_group`, `getpid`, `sched_yield`, `nanosleep`, `-ENOSYS` for the rest) behind a per-process ABI table; every user pointer validated before use; a static ELF64 loader fed by Limine modules; a fault, privileged instruction or undefined instruction in ring 3 kills only that process |
| Next | a filesystem and a native IgniOS system call ABI |

## Quick start

You need Nix with flakes. The flake provides clang, lld, Limine, QEMU, OVMF, mtools and the font.

```sh
nix develop
make run
```

QEMU opens a window. Click it to give it the keyboard and type at the prompt. The terminal shows the serial log.

The build also needs an Ignis compiler with freestanding support (Ignis `main` from October 2026 or later). The Makefile uses the `ignis` on your `PATH`; point elsewhere with `make IGNIS=/path/to/ignis`.

## Make targets

| Target | What it does |
|---|---|
| `kernel` | Builds `build/kernel.elf` |
| `user` | Builds the user program `build/hello.elf` from `user/hello` and `user/lib` |
| `image` | Builds `build/ignios.img`, a FAT32 EFI system partition with Limine, the kernel and the user program |
| `run` | Boots in QEMU with the serial console on stdio |
| `run-headless` | Boots without a display and checks the banner and prompt in `build/serial.log` |
| `screenshot` | Boots headless and saves the screen to `build/screen.png` |
| `keytest` | Types keys through the QEMU monitor and checks the echo |
| `font` | Regenerates `kernel/src/font_8x16.ign` from the Spleen package |
| `clean` | Removes `build/` |

## How it is built

Ignis compiles the whole kernel to one C unit, which clang compiles for `x86_64-unknown-none` with kernel flags (no red zone, no SSE, `-mcmodel=kernel`). The few routines that cannot be written in Ignis are small `.S` files under `kernel/src/arch/x86_64/`: interrupt entry stubs, the code segment reload, the stack switch, the ring 3 entry and the `SYSCALL` stub, and the throwaway user programs of the boot self-tests. `ld.lld` links everything with `kernel/linker.ld`, and `mtools` writes the boot image. No cross GCC is involved.

User programs are Ignis projects under `user/` built with `std = false` and the small user standard library in `user/lib` (`std::sys` wraps the system calls in inline asm, `std::io` prints). The Makefile links each one with `user/user.ld` into a static ELF64 at `0x400000`, copies it into the boot image and `boot/limine.conf` lists it as a Limine module. The kernel runs `hello` at boot, before the keyboard line, and `run hello` at the prompt runs it again.

## Layout

New to the code? [docs/READING.md](docs/READING.md) is a reading guide in the order the code runs, with a virtual address space map and the boot log explained line by line.

```
kernel/src/main.ign            kmain, banner, panic handler, terminal loop
kernel/src/limine.ign          Limine requests and responses
kernel/src/console.ign         framebuffer text console
kernel/src/keyboard.ign        scancode set 1 decoder
kernel/src/ps2.ign             PS/2 controller
kernel/src/interrupts.ign      exception reports and interrupt dispatch
kernel/src/acpi.ign            RSDP, XSDT and MADT parsing
kernel/src/timer.ign           APIC timer calibration and tick counter
kernel/src/pmm.ign             physical frame allocator
kernel/src/vmm.ign             page tables: map, unmap, translate, flush, in the kernel's or any address space
kernel/src/address_space.ign   per-process PML4, user pages, user-pointer copies, destroy
kernel/src/process.ign         process table, start from code or ELF, exit, kill, wait
kernel/src/syscall.ign         ABI tables and the Linux syscall handlers
kernel/src/elf.ign             static ELF64 loader
kernel/src/modules.ign         Limine modules, mapped read only
kernel/src/programs.ign        run a module by name
kernel/src/user_test.ign       boot-time user mode and isolation tests
kernel/src/heap.ign            kernel heap: first-fit allocator over PMM-backed pages
kernel/src/hhdm.ign            physical memory through the higher half direct map
kernel/src/scheduler.ign       kernel threads, run queue, sleep and timer preemption
kernel/src/scheduler_test.ign  boot-time scheduler self-tests
kernel/src/thread_commands.ign the `ps` and `threads` terminal commands
kernel/src/arch/x86_64/        GDT, IDT, PIC, local APIC, IOAPIC, PIT, port I/O, CPU helpers and stack switching, .S stubs
kernel/linker.ld               higher-half layout
user/lib/                      the user standard library (syscalls, text output)
user/hello/                    the first user program
user/user.ld                   user program layout
boot/limine.conf               boot entry and the user program module
docs/READING.md                reading guide: file by file, address space map, annotated boot log
scripts/                       font generator, screenshot and key test drivers
```

## Acknowledgements

The overall approach (Limine, one generated C unit, clang and lld, assembly entry stubs) follows [Vinix](https://github.com/vlang/vinix), the operating system written in V.

## License

GPL-3.0-only, the same as the Ignis compiler. See `LICENSE`.

The console font is Spleen 8x16 by Frederic Cambus, under the BSD 2-Clause license. See `THIRD_PARTY.md` and `LICENSES/`.
