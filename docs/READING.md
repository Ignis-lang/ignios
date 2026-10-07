# Reading the IgniOS source

This guide gives a reading order for the whole source tree. It follows the order in which the code runs, from the bootloader to the first user program. Each file has a short paragraph with what to look at and which concept document to read next to it. A map of the virtual address space and the boot log, annotated line by line, close the guide.

The kernel is split into subsystems, one directory each. The section "The subsystems" below says what each one owns and what it may import. Names in the text are written as the code writes them: `Mm::Pmm::allocateFrame` is the function `allocateFrame` in the namespace `Pmm` of the subsystem `Mm`, and it lives in `kernel/src/mm/pmm.ign`.

Every `.ign` file starts with a `//!` header that explains the file, and every declaration has a `///` comment. The `mod.ign` of a subsystem has its public API and its dependencies. The assembly files carry comments on every routine. Read the header of a file first, then the code.

## Quick path

1. Read `kernel/src/main.ign`, which is the boot sequence and is short, then the boot log below. They name every step.
2. Follow the parts below in order. Each part ends in something you can see in the boot log.
3. Run `make run-headless` and compare the output of `build/serial.log` with the annotated log.

## Concept documents

The concept documents explain the x86_64 and kernel background, and this guide refers to them by number ("doc 09"). They are the Atlas "Concepts" collection. The source comments point to the same numbers.

| Doc | Topic | Doc | Topic |
|---|---|---|---|
| 00 | Index and glossary | 08 | Physical memory |
| 01 | Boot | 09 | Paging |
| 02 | CPU modes and toolchain | 10 | Kernel heap |
| 03 | GDT and TSS | 11 | Debugging |
| 04 | Interrupts and exceptions | 12 | ACPI, IOAPIC and the APIC timer |
| 05 | Interrupt controllers | 13 | Kernel threads and scheduling |
| 06 | Devices and I/O | 14 | Address spaces and user mode |
| 07 | Framebuffer console | 15 | System calls and ELF programs |

## The subsystems

Each subsystem is a directory under `kernel/src/` with a `mod.ign` facade. The facade declares the namespace (`export namespace Mm {}`) and imports the files that add to it, the same way `std/libc` does. `ignis.toml` has one alias per subsystem, so another subsystem writes `import Mm from "@mm"` and never imports a file inside the directory. A file that no import reaches is not compiled, even when assembly refers to its `@externName` symbols, which is why every file is listed in its facade.

| Directory | Namespace | Alias | Imports | Owns |
|---|---|---|---|---|
| `lib/` | `Lib` | `@lib` | nothing | `Mem`, `Format`, `ScancodeQueue` |
| `arch/` | `Arch` | `@arch` | nothing | `Cpu`, `Port`, `Gdt`, `Idt`, `Pic`, `Pit`, `Context`, `UserMode`, `InterruptFrame`, all `.S` files |
| `boot/` | `Boot` | `@boot` | nothing | `Limine`, `Hhdm` |
| `drivers/` | `Drivers` | `@drivers` | Arch, Boot, Lib | `Serial`, `Console`, `Color`, `Font`, `Ps2`, `Keyboard` |
| `acpi/` | `Acpi` | `@acpi` | Boot, Drivers | `Rsdp`, `Xsdt`, `Madt`, `Table` |
| `mm/` | `Mm` | `@mm` | Arch, Boot, Drivers, Lib | `Pmm`, `Vmm`, `AddressSpace`, `Heap`, `Modules` |
| `apic/` | `Apic` | `@apic` | Acpi, Arch, Drivers, Mm | `Lapic`, `Ioapic` |
| `time/` | `Time` | `@time` | Apic, Arch, Drivers | `Timer` |
| `sched/` | `Sched` | `@sched` | Arch, Mm, Time | `Thread`, `Scheduler` |
| `proc/` | `Proc` | `@proc` | Arch, Boot, Drivers, Lib, Mm, Sched | `Process`, `Elf`, `Programs` |
| `syscall/` | `Syscall` | `@syscall` | Arch, Drivers, Mm, Proc, Sched, Time | `Operation`, `Linux` |
| `trap/` | `Trap` | `@trap` | Apic, Arch, Drivers, Proc, Sched, Time | `Exception`, `Setup`, the dispatcher |
| `shell/` | `Shell` | `@shell` | Arch, Drivers, Lib, Proc, Sched, Time | `Terminal`, `Commands`, `ThreadCommands` |
| `tests/` | `Tests` | `@tests` | Arch, Boot, Drivers, Mm, Proc, Sched, Time | the boot self-tests |

`main.ign` imports every facade and `panic.ign`. The compiler rejects an import cycle, so the table is a layering: a subsystem imports only rows above it. A few places in it need a reason, because a plain layering would put them elsewhere.

- **`Apic` is not in `Arch`.** The local APIC maps its register page with `Mm::Vmm::map` and the IOAPIC reads the MADT, so they need `Mm` and `Acpi`. `Mm` imports `Arch`, so `Arch` cannot import them back. `Arch::Idt::initialize` takes the spurious vector as a parameter for the same reason.
- **`Trap` is not in `Arch`.** The dispatcher the interrupt stubs call reaches into the drivers, the clock, the scheduler and the processes. It also owns the GDT, IDT and `SYSCALL` setup steps that print a log line (`Trap::Setup`), because `Arch` cannot print.
- **`Mm::Modules` is not in `Boot`.** It maps the module pages with `Mm::Vmm::mapRange`.
- **`Mm` and `Acpi` import `Drivers`** to print their boot report. `Drivers` imports none of them.

## Contents

| Part | Topic | Files |
|---|---|---|
| 1 | Build and boot | `Makefile`, `ignis.toml`, `kernel/linker.ld`, `boot/limine.conf`, `boot/mod.ign`, `boot/limine.ign` |
| 2 | The entry point | `main.ign`, `panic.ign`, the `mod.ign` files |
| 3 | Serial port, console and library | `lib/mod.ign`, `lib/format.ign`, `lib/mem.ign`, `arch/x86_64/io.ign`, `drivers/serial.ign`, `drivers/font.ign`, `drivers/font_8x16.ign`, `drivers/console.ign` |
| 4 | CPU tables and interrupts | `arch/x86_64/cpu.ign`, `gdt.ign`, `gdt_asm.S`, `idt.ign`, `interrupt_frame.ign`, `interrupt_asm.S`, `trap/dispatch.ign`, `trap/exception.ign`, `trap/setup.ign` |
| 5 | Memory | `boot/hhdm.ign`, `mm/pmm.ign`, `mm/vmm.ign`, `mm/heap.ign`, `mm/address_space.ign` |
| 6 | ACPI, APIC and the timer | `acpi/*.ign`, `arch/x86_64/pic.ign`, `apic/lapic.ign`, `apic/ioapic.ign`, `arch/x86_64/pit.ign`, `time/timer.ign` |
| 7 | Keyboard | `drivers/ps2.ign`, `lib/scancode_queue.ign`, `drivers/keyboard.ign` |
| 8 | Threads, scheduling and the shell | `arch/x86_64/context.ign`, `context_asm.S`, `sched/thread.ign`, `sched/scheduler.ign`, `shell/*.ign` |
| 9 | User mode | `arch/x86_64/usermode.ign`, `usermode_asm.S`, `proc/process.ign`, `syscall/*.ign`, `proc/elf.ign`, `mm/modules.ign`, `proc/programs.ign`, `user/` |
| 10 | Boot self-tests | `tests/*.ign`, `arch/x86_64/user_test_asm.S` |
| 11 | Scripts | `scripts/` |

All paths are under `kernel/src/` unless they say otherwise. The assembly files and the architecture code are in `kernel/src/arch/x86_64/`.

---

## Part 1. Build and boot

Read these first. They define what the kernel is made of and how it gets the machine. Concept docs 01 and 02.

**`Makefile`.** The header comment draws the build pipeline. Ignis compiles all of `kernel/src/**/*.ign` to one C file, clang compiles it, clang assembles the `.S` files, `ld.lld` links them with `kernel/linker.ld`, and `mtools` puts the result in a FAT32 disk image. Look at `QEMU_FLAGS` (q35 machine, OVMF firmware as two flash drives, `-no-reboot`) and at the `run-headless` target, which is the quickest way to see a boot. One thing to know: the link order of the `.S` objects follows the order of `find`, so the layout of `build/kernel.elf` can differ between checkouts.

**`ignis.toml`.** The Ignis project file. `std = false` means no standard library. The `cflags` comment explains each clang flag (no red zone, no SSE, kernel code model, no stack protector). Doc 02.

**`kernel/linker.ld`.** Puts the kernel at `0xffffffff80000000` in three segments (text, rodata, data) with the page-aligned boundary symbols `__text_start` and so on. The table in the header shows the layout. `Mm::Vmm::mapKernelImage` uses these symbols to map each segment with its own permissions. Doc 01.

**`boot/limine.conf`.** The Limine configuration: the kernel path, and the `hello.elf` module that `run hello` starts. Doc 01.

**`boot/mod.ign` and `boot/limine.ign`.** The Limine boot protocol. A request is a global record with a fixed identifier that Limine finds by scanning the loaded image and answers by writing a pointer into its `response` field. Look at the diagram in the header and at `readResponse`, which reads the pointer with a volatile load because Limine wrote it behind the compiler's back. The memory map entry types are in the table above `MEMMAP_USABLE`. `requireBaseRevision` and `requireFramebuffer` are the two checks `kmain` makes before anything else. Doc 01.

## Part 2. The entry point

**`main.ign`.** `kmain` is the ELF entry point. The header lists the boot sequence with the subsystem and concept doc of each step, and the body follows it in order. `kmain` is a list of calls: each step belongs to a subsystem, and the subsystem prints its own boot log line (`Mm::Pmm::report`, `Apic::Lapic::report`, `Time::Timer::report` and so on). The self-tests of `Tests` run in the places where the subsystem they check is ready. Read `kmain` top to bottom. The comments in it give the reasons for the order of the GDT and IDT, of the PMM, VMM and heap, and of the keyboard last. Docs 01, 04 and 11.

**`panic.ign`.** `onPanic`, the one place every panic ends. The panic report goes to COM1 and, once it is up, to the console.

**The `mod.ign` files.** Read the header of each one when you enter a subsystem: it has the API table and the imports with the reason for each. Then read the namespaces it lists.

## Part 3. Serial port and console

**`lib/mod.ign`.** The library facade: the three files of `Lib`, which import nothing from the kernel.

**`arch/x86_64/io.ign`.** Two functions, `in` and `out` on a port. The header table lists every port the kernel uses and the file that uses it. Doc 06.

**`drivers/serial.ign`.** The COM1 driver, polled, no interrupts. The header has the register map and the values written by `initialize`. Look at the second write to `INTERRUPT_ENABLE` in `initialize`, which is the divisor high byte because DLAB is set. Doc 06.

**`lib/format.ign`.** Number to text through a callback, so serial and console share the code and nothing needs a buffer or a heap. Doc 06.

**`lib/mem.ign`.** `memcpy`, `memset`, `memmove` and `memcmp`, which clang calls on its own. They use `rep movsb` and `rep stosb` in inline assembly so that clang does not turn the loop back into a call to itself. Look at the direction flag handling in `move`. Doc 02.

**`drivers/font.ign` and `drivers/font_8x16.ign`.** The 8x16 bitmap font. `font_8x16.ign` is generated by `scripts/gen-font.py` and must not be edited by hand. `font.ign` has an example glyph bitmap and the address formula. Doc 07.

**`drivers/console.ign`.** The text console. Look at the geometry diagram (pitch and the pixel address formula), at the cell grid with its character and color arrays, and at how the cursor is drawn from the cell copy instead of reading the framebuffer back. Every public function disables interrupts so a line is never interleaved with another thread's output. Every byte is mirrored to COM1, which is why `build/serial.log` contains the whole screen. `printBanner` draws the banner and the framebuffer line. Doc 07.

## Part 4. CPU tables and interrupts

Read `gdt.ign` before `idt.ign`, because the IDT gates name a GDT selector and the double fault gate names a TSS stack. Docs 03 and 04.

**`arch/x86_64/cpu.ign`.** Short wrappers for `cli`, `sti`, `hlt`, `rdmsr`, `wrmsr` and control registers. `saveAndDisableInterrupts` and `restoreInterrupts` are the kernel's only mutual exclusion: with one processor, interrupts off means nothing else runs. Doc 02.

**`arch/x86_64/gdt.ign` and `gdt_asm.S`.** The GDT has five entries and the TSS descriptor. The header decodes every descriptor value bit by bit and draws the TSS. The selector order (kernel code, kernel data, user data, user code) is the order `SYSCALL` and `SYSRET` need. `gdt_asm.S` reloads `CS` with a far return, because `CS` cannot be loaded with `mov`. Doc 03.

**`arch/x86_64/idt.ign`.** The 256-entry table. The header draws the 16-byte gate and explains the attribute byte `0x8E`. Only 50 gates are filled (vectors 0 to 48 and the APIC spurious vector 255). Doc 04.

**`arch/x86_64/interrupt_asm.S`.** One thunk per vector, then one common stub. The header draws what the stack looks like when the dispatcher runs, which is the `Arch::InterruptFrame` record of `interrupt_frame.ign`. Notice that the thunk pushes a dummy error code for the vectors where the CPU pushes none, so the frame has one shape. Doc 04.

**`trap/dispatch.ign`, `trap/exception.ign` and `trap/setup.ign`.** `Trap::dispatch` is the one place every vector arrives. The header diagram shows the routing. `exception.ign` has the table of exceptions: read `killUserProcess` and `isUserFault` for the rule that a fault in ring 3 kills the process and a fault in ring 0 halts the machine. `setup.ign` has the three boot steps that install the GDT, the IDT and the `SYSCALL` registers and log what they did. Doc 04.

## Part 5. Memory

Read in this order: `hhdm`, `pmm`, `vmm`, `heap`, `address_space`. Each uses the one before. `mm/modules.ign` comes with part 9.

**`boot/hhdm.ign`.** Physical address `p` is at `offset + p` in the higher half direct map. Two functions. Doc 09.

**`mm/pmm.ign`.** The frame allocator, a bitmap with one bit per 4 KiB frame. The header shows how a bit maps to a frame number and an address, and where the bitmap itself is placed. Frame 0 is never handed out so address 0 can mean "no frame". Doc 08.

**`mm/vmm.ign`.** The page tables. This is the longest explanation in the tree. The header shows the address split (9+9+9+9+12 bits), the page table entry bits, the PAT memory types and the virtual address space map. `initialize` has the numbered order of operations. The `*In` functions work on any PML4, which is what lets the same code build a process address space. Doc 09.

**`mm/heap.ign`.** A first-fit allocator over a region that grows on demand. The header draws the 16-byte block header, the address-ordered free list, how an aligned request splits a block and how a free merges neighbours. The compiler's allocation handlers (`onAllocate` and `onFree`) at the end of the namespace are what escaping closures use. Doc 10.

**`mm/address_space.ign`.** One PML4 per process. The lower half is private and the upper half is a copy of the kernel's 256 entries, so kernel mappings made later still show up in every process. The user-pointer functions (`copyFromUser` and the others) translate through the process page tables instead of dereferencing a user address. Doc 14.

## Part 6. ACPI, APIC and the timer

Docs 05 and 12.

**`acpi/mod.ign`, `rsdp.ign`, `xsdt.ign`, `madt.ign`, `table.ign`.** Finds the MADT through the RSDP and the XSDT. `mod.ign` draws the walk, `rsdp.ign` and `table.ign` show the structure layouts, `xsdt.ign` searches the root table by signature and `madt.ign` parses the interrupt controller entries. The parser reads every field byte by byte because the tables are packed. Only the local APIC address, the IOAPICs and the interrupt source overrides are kept.

**`arch/x86_64/pic.ign`.** The legacy 8259. The kernel remaps it to vectors `0x20` to `0x2F` and masks every line. The table in the header lists the four initialization words. It stays remapped so a spurious interrupt lands on a known vector.

**`apic/lapic.ign`.** The local APIC. Look at the register table and the LVT entry layout. `initialize` maps the page uncached, enables the APIC through the spurious vector register and sets LINT0 masked and LINT1 to NMI.

**`apic/ioapic.ign`.** The IOAPIC and its redirection entries. The header shows the 64-bit entry bit by bit. `route` writes the high half before the low half, because the low write is the one that unmasks the pin.

**`arch/x86_64/pit.ign`.** The 8254 timer as a stopwatch: channel 2, mode 0, polled through port `0x61`. Used once.

**`time/timer.ign`.** Measures the APIC timer against the PIT for 50 ms, derives the initial count for 100 Hz, and starts the timer in periodic mode. The interrupt handler only increments a counter. The header shows the calibration arithmetic with the numbers from a real run.

## Part 7. Keyboard

Doc 06. `kmain` enables the keyboard last, but the path it uses runs through the IOAPIC route set up in part 6.

**`drivers/ps2.ign`.** The 8042 controller. The header gives the status bits and the configuration byte. `handleInterrupt` runs in the IRQ1 handler and moves bytes into the queue.

**`lib/scancode_queue.ign`.** A single-producer single-consumer ring buffer between the interrupt handler and the terminal. There is no lock. Each side writes only its own index, and every access is volatile.

**`drivers/keyboard.ign`.** The scancode set 1 decoder with a US layout. The header lists the make codes and draws the state machine. It handles Shift, Caps Lock, Ctrl, the `0xE0` prefix and the six-byte Pause sequence. `Drivers::Keyboard::initialize` brings the controller up and prints the keyboard line.

## Part 8. Threads, scheduling and the shell

Doc 13.

**`arch/x86_64/context.ign` and `context_asm.S`.** The context switch. A thread that is not running is a saved stack pointer. The header of `context_asm.S` draws the stack of a thread that has never run, and the trampoline that starts it. A switch is an ordinary function call that pushes six registers, swaps `rsp` and pops six registers. It must run with interrupts off.

**`sched/thread.ign`.** The thread table: one slot per thread, its state and its stack. The header has the state diagram and the layout of a thread stack with its guard page.

**`sched/scheduler.ign`.** The run queue, sleeping and the timer-driven preemption. The header has the call chain from the timer interrupt to a switch. Look at how a dead thread's stack is freed by the next thread (`reapZombie`), because a thread cannot free the stack it is running on. Sleeping and waking are here and not in a file of their own, because `sleep` calls `switchToNext` and `switchToNext` calls the wake-up scan.

**`shell/terminal.ign`.** The terminal loop the boot thread becomes. It is the clearest example of the `cli`, check, `sti; hlt` pattern that avoids a lost wakeup: the queue is tested with interrupts off so a key cannot arrive between the test and the sleep.

**`shell/commands.ign` and `shell/thread_commands.ign`.** The commands: `uptime`, `ps`, `threads` and `run NAME`.

## Part 9. User mode

Docs 14 and 15.

**`arch/x86_64/usermode.ign` and `usermode_asm.S`.** How the CPU enters and leaves ring 3. `ignis_enter_user` builds an `iretq` frame. `initialize` programs `IA32_STAR`, `IA32_LSTAR` and `IA32_FMASK`, and the header shows the bit fields. The `SYSCALL` entry stub in `usermode_asm.S` is the most delicate code in the tree: it switches stacks by hand, builds the same frame the interrupt stub builds, and refuses to execute `SYSRET` with a non-canonical return address.

**`proc/process.ign`.** The process table. A process is a slot plus a kernel thread that owns the address space. The header draws the lifetime from `startElf` to `wait`.

**`syscall/dispatch.ign`, `operation.ign` and `linux/`.** Two-step dispatch: the call number maps to an operation through a per-process table, then the operation runs. `dispatch.ign` draws the flow, `operation.ign` has the ABI independent operations, `linux/table.ign` lists the calls and `linux/write.ign` and `linux/nanosleep.ign` are the handlers. Every user pointer goes through `Mm::AddressSpace::copyFromUser` or `copyToUser`, and a bad one is `-EFAULT`.

**`proc/elf.ign`.** The ELF64 loader. The header maps the segments of `hello.elf` to user addresses and shows the header structures. It refuses a segment that is both writable and executable.

**`mm/modules.ign` and `proc/programs.ign`.** Find a Limine module by its configuration string, and run it as a process.

**`user/`.** The user side. `lib/sys.ign` wraps the `syscall` instruction, `lib/io.ign` prints, and `hello/src/main.ign` is the program. `user/user.ld` places it at `0x400000`.

## Part 10. Boot self-tests

**`tests/`.** One file per check, run by `kmain` where the subsystem is ready. Each prints one line and panics on the first violation, so a boot that continues has passed it. The tests use only the public functions of the subsystems. `pmm.ign`, `vmm.ign`, `heap.ign`, `address_space.ign`, `timer.ign` and `context.ign` check the primitives. `scheduler.ign` runs round-robin order, sleeping, a full table, one address space per thread and preemption of threads that never yield. `user.ign` and `arch/x86_64/user_test_asm.S` hold thirteen throwaway ring 3 programs. Four behave (exit, registers, spin, system calls) and nine do something forbidden. The kernel must kill each of the nine with the right status.

## Part 11. Scripts

**`scripts/keytest.sh` and `scripts/screenshot.sh`.** Boot QEMU headless, wait for the prompt on the serial log, and drive the QEMU monitor (`sendkey`, `screendump`). `keytest.sh` also checks the echo. **`scripts/gen-font.py`** regenerates `drivers/font_8x16.ign` from the Spleen BDF file. **`flake.nix`** provides the toolchain.

---

## Virtual address space map

Paging is set up in `mm/vmm.ign`. The kernel uses one PML4 entry per region so the regions cannot collide. See doc 09.

```text
0x0000000000000000  ┌──────────────────────────────────────────┐
                    │ page 0: never mapped (null pointers)     │
0x0000000000400000  ├──────────────────────────────────────────┤
                    │ user program: text, rodata, data, bss    │  PML4 0..255
                    │ (from the ELF, one region per segment)   │  private to each
0x00007FFFFFFF7000  ├──────────────────────────────────────────┤  process
                    │ user stack: 8 pages, grows down          │
0x00007FFFFFFFF000  ├──────────────────────────────────────────┤
                    │ USER_LIMIT: this page is never mapped    │
0x0000800000000000  ├─ - - - - non-canonical hole - - - - - - -┤
0xFFFF800000000000  ├──────────────────────────────────────────┤  PML4 256
                    │ direct map: physical p at offset + p     │
0xFFFFA00000000000  ├──────────────────────────────────────────┤  PML4 320
                    │ local APIC page (uncached)               │
0xFFFFA00000010000  │ IOAPIC pages, one per chip (uncached)    │
0xFFFFB00000000000  ├──────────────────────────────────────────┤  PML4 352
                    │ thread kernel stacks, 20 KiB per slot    │
0xFFFFC00000000000  ├──────────────────────────────────────────┤  PML4 384
                    │ kernel heap (up to 256 MiB)              │
0xFFFFE00000000000  ├──────────────────────────────────────────┤  PML4 448
                    │ TEST_ADDRESS, used by self-tests         │
0xFFFFFFFF80000000  ├──────────────────────────────────────────┤  PML4 511,
                    │ kernel image: text, rodata, data, bss    │  PDPT 510
                    └──────────────────────────────────────────┘
```

| Region | Starts at | Set up by | Notes |
|---|---|---|---|
| User program | `0x400000` | `Proc::Elf::load` | Each `PT_LOAD` segment gets its own pages. Writable pages are never executable. |
| User stack | `0x7FFFFFFF7000` to `0x7FFFFFFFF000` | `Proc::Process::mapStack` | 8 zeroed pages, no-execute. The first stack pointer is the top minus 8. |
| Direct map | `0xFFFF800000000000` | `Mm::Vmm::mapDirectMap` | The offset is Limine's. Uses 2 MiB pages where it can. The kernel image is left out. The framebuffer is mapped write-combining. |
| APIC pages | `0xFFFFA00000000000` | `Apic::Lapic::initialize`, `Apic::Ioapic::initialize` | Uncached. |
| Thread stacks | `0xFFFFB00000000000` | `Sched::Thread::createThread` | 5 pages per slot, the lowest is an unmapped guard page. |
| Kernel heap | `0xFFFFC00000000000` | `Mm::Heap::grow` | 16 pages at a time, 256 MiB at most. |
| Test page | `0xFFFFE00000000000` | `Tests::Vmm::run` | Mapped and unmapped by the tests. |
| Kernel image | `0xFFFFFFFF80000000` | `Mm::Vmm::mapKernelImage` | Text is read and execute, rodata is read, data and bss are read and write. |

Physical memory is not drawn because it depends on the machine. `Mm::Pmm` takes it from the Limine memory map: only `usable` regions are handed out, frame 0 is never handed out, and the bitmap sits in the first usable region at or above 1 MiB that is large enough.

## Three paths worth tracing

Follow each one with the code open. They connect the parts above.

| Path | Steps |
|---|---|
| A key press | keyboard, 8042, IRQ1, IOAPIC pin 1, vector `0x21`, `interrupt_asm.S` thunk 33, `Trap::dispatch`, `Drivers::Ps2::handleInterrupt`, `Lib::ScancodeQueue::push`, `Apic::Lapic::endOfInterrupt`. Later `Shell::Terminal::run` pops the byte and `Drivers::Keyboard::decode` turns it into a character. |
| A preemption | LAPIC timer, vector `0x30`, `Trap::dispatch`, `Time::Timer::handleTick`, `Apic::Lapic::endOfInterrupt`, `Sched::Scheduler::onTick`, `switchToNext`, `Arch::Context::switchTo`, `ignis_switch_context`. The other thread returns from its own `switchTo` and finishes its own interrupt. |
| A system call | `syscall` in ring 3, `ignis_syscall_entry`, `Syscall::dispatch`, `Syscall::Linux::write`, `Mm::AddressSpace::copyFromUser`, `Drivers::Console::writeChar`, `sysretq`. |

## The boot log, line by line

This is the serial log of `make run-headless` (`build/serial.log`) on the QEMU q35 machine with OVMF and 256 MiB of RAM. Values such as addresses, tick counts and the number of switches vary between runs and machines, and the explanation says when a value is fixed by the code. "Serial only" marks lines that `kmain` writes to COM1 before the console exists or deliberately not to the screen. Every other line is on the screen too.

The log starts with firmware output (terminal escape sequences and `BdsDxe: loading Boot0002 ...`). It comes from OVMF before Limine runs and is not the kernel.

### Early boot (serial only)

```text
IgniOS booting
```
`Drivers::Serial::initialize` finished and `kmain` wrote the first line (`main.ign`). Limine has handed over control. The kernel runs in ring 0 on Limine's stack with interrupts off.

```text
gdt: cs=0x0000000000000008 tr=0x0000000000000028
```
`Trap::Setup::initializeGdt` read `CS` and the task register back from the CPU. `0x08` is the kernel code selector and `0x28` the TSS selector, which proves the far return and `ltr` in `Arch::Gdt::initialize` worked. Doc 03.

```text
idt: 50 gates loaded
```
`Arch::Idt::initialize` filled 49 gates (vectors 0 to 48) and the spurious vector 255. The text is a constant in `Trap::Setup::initializeIdt`, not a count. Doc 04.

### The screen comes up

```text
 IgniOS  an x86_64 kernel written in Ignis
```
`Drivers::Console::printBanner`, the first console line (`Drivers::Console::initialize` ran just before). Yellow on blue, then cyan on black.

```text
framebuffer: 1280x800, pitch 5120, bpp 32, 160x50 cells
```
`Drivers::Console::reportFramebuffer`. From the Limine framebuffer: 1280 by 800 pixels, 5120 bytes per row (1280 x 4, no padding here), 32 bits per pixel. The console grid is 1280 / 8 = 160 columns by 800 / 16 = 50 rows. Doc 07.

```text
memory map: 36 entries, hhdm offset 0xffff800000000000
```
`Mm::Pmm::reportMemoryMap`. The Limine memory map has 36 entries. `0xffff800000000000` is where physical address 0 appears in virtual memory (the direct map). Doc 08.

### Memory

```text
pmm: 54015 usable frames, 54013 free (210 MiB)
```
`Mm::Pmm::initialize` counted 54015 usable 4 KiB frames, and `Mm::Pmm::report` printed the line. Two are already taken: they hold the bitmap (1024 words of 8 bytes = 8 KiB = 2 frames). The size in MiB is `free * 4 / 1024` with integer division. Doc 08.

```text
pmm: self-test ok
```
`Tests::Pmm::run` allocated and freed 8 frames and checked alignment, uniqueness, the free count and reuse.

```text
vmm: cr3 switched, cr3 0x0000000000001000, pml4 0x0000000000001000
```
`Mm::Vmm::initialize` built the kernel page tables and loaded CR3, and `Mm::Vmm::report` printed the line. The PML4 is at physical address `0x1000`, which is frame 1: the lowest free frame, since frame 0 is never handed out. Both numbers are the same because `Mm::Vmm::rootTable` is the CR3 value. Doc 09.

```text
vmm: self-test ok
```
`Tests::Vmm::run` mapped a frame at a test address, wrote through it, read it through the direct map, and unmapped it.

```text
modules: hello is /hello.elf, 13152 bytes at 0xffff80000bf68000
```
The Limine module from `boot/limine.conf`. `hello` is the `module_string`, `/hello.elf` the path. `Mm::Modules::initialize` mapped its pages read only. The address is in the direct map, so the file sits at physical `0x0bf68000`. Doc 15.

```text
heap: self-test ok, 1092 KiB mapped, 0 bytes in use
```
`Tests::Heap::run` checked alignment, reuse, merging, growth (it allocates 1 MiB) and the compiler allocation handlers. 1092 KiB of heap pages stayed mapped and every block was freed. Doc 10.

```text
address space: self-test ok, private user half, shared kernel half, frames returned
```
`Tests::AddressSpace::run` created two spaces, checked that the lower half is private and the upper half shared (including a mapping made after the spaces existed), switched CR3 between them, and destroyed them without leaking frames. Doc 14.

```text
usermode: syscall enabled, star 0x0010000800000000, lstar 0xffffffff800112fc, fmask 0x0000000000044700
```
Serial only. `Trap::Setup::initializeUserMode` called `Arch::UserMode::initialize`, which set `EFER.SCE` and wrote three MSRs. `star` is `(0x10 << 48) | (0x08 << 32)`: `SYSCALL` loads CS `0x08`, `SYSRET` loads CS `0x23` and SS `0x1B`. `lstar` is the address of the entry stub and changes with every build. `fmask` `0x44700` is the flags `SYSCALL` clears: TF, IF, DF, NT and AC. Doc 14.

### ACPI and interrupt controllers

```text
acpi: rsdp 0x000000000fe6b014, revision 2, oem BOCHS , xsdt 0x000000000fe6a0e8 with 6 tables, madt 0x000000000fe65000
```
`Acpi::report` (the `madt:` lines come from `Acpi::Madt::report`). The RSDP is at physical `0xfe6b014`, revision 2 (so the XSDT is used), the OEM id is `BOCHS ` (QEMU), the XSDT lists 6 tables and one of them is the MADT. Doc 12.

```text
madt: lapic 0x00000000fee00000, 1 of 1 processors enabled, 8259 present, 1 ioapic, 5 overrides
```
From the MADT. The local APIC is at the standard `0xFEE00000`. One processor, the dual 8259 flag is set, one IOAPIC, five interrupt source overrides.

```text
madt: ioapic id 0 at 0x00000000fec00000, gsi base 0
```
The IOAPIC, at the standard `0xFEC00000`, serving global system interrupts from 0.

```text
madt: override ISA IRQ 0 -> GSI 2, default polarity, default trigger
madt: override ISA IRQ 5 -> GSI 5, active high, level
madt: override ISA IRQ 9 -> GSI 9, active high, level
madt: override ISA IRQ 10 -> GSI 10, active high, level
madt: override ISA IRQ 11 -> GSI 11, active high, level
```
The interrupt source overrides. The legacy timer IRQ 0 is wired to GSI 2. IRQs 5, 9, 10 and 11 are level triggered. IRQ 1 (the keyboard) has no override, so it stays GSI 1 with ISA defaults. Doc 12.

```text
lapic: base 0x00000000fee00000, id 0, version 0x0000000000050014, msr enabled 1, svr enabled 1, LINT0 masked, LINT1 NMI
```
`Apic::Lapic::initialize` ran after `Arch::Pic::initialize`, and `Apic::Lapic::report` printed the line. Version `0x14` with the last LVT entry number 5 in bits 23 to 16. Both enable bits are set: bit 11 of `IA32_APIC_BASE` and bit 8 of the spurious vector register. The last two words are what `initialize` wrote, not values read back. Doc 05.

```text
ioapic: id 0, version 0x0000000000000011, 24 redirection entries, gsi base 0
```
`Apic::Ioapic::initialize` mapped the chip and masked all 24 entries (the highest entry number is in the version register).

```text
ioapic: keyboard IRQ 1 -> GSI 1, vector 0x0000000000000021, entry 0x0000000000000021
```
`Apic::Ioapic::routeIsa(1, 0x21)`. IRQ 1 becomes GSI 1 and interrupts on vector `0x21`. The raw redirection entry is `0x21`, which means vector `0x21` with every other bit clear: unmasked, edge, active high, fixed delivery, physical destination, APIC id 0. Doc 12.

```text
pic: masked, imr 0x000000000000ffff
```
Both 8259 mask registers read back all ones, so the legacy controller delivers nothing. Doc 05.

### Timer and scheduler

```text
timer: calibrated on PIT channel 2: 62542704 Hz (divide 16), initial count 625427, 100 Hz periodic, vector 0x0000000000000030
```
`Time::Timer::initialize` measured the APIC timer over 50 ms of PIT time. It counts at about 62.5 MHz at the divide-by-16 setting. The initial count is that rate divided by 100, so the timer interrupts every 10 ms on vector `0x30`. The numbers differ between runs. Doc 12.

```text
timer: self-test ok, 10 ticks so far
```
`Tests::Timer::run` enabled interrupts and slept until 10 ticks (100 ms) had arrived.

```text
context: self-test ok, stack switch, argument, alignment and registers checked
```
`Tests::Context::run` switched into a hand-built thread and back three times. Doc 13.

```text
scheduler: self-test ok, round-robin, sleep and slot reuse, 68 switches
```
`Tests::Scheduler::runCooperative`. The count is the number of context switches so far and varies a little.

```text
scheduler: address-space self-test ok, each thread ran in its own CR3 and every frame came back
```
`Tests::Scheduler::runAddressSpaces`: two threads read the same user address while yielding and each saw its own page.

```text
scheduler: preemption self-test ok, two threads that never yield shared the processor, 6 preemptions
```
`Sched::Scheduler::enablePreemption` was called, then `Tests::Scheduler::runPreemptive`. The timer took the processor away from spinning threads at least twice (the number varies).

### User mode self-tests

Each program here is one of the throwaway ring 3 programs of `user_test_asm.S`, run by `Tests::User::run`. The kernel numbers processes from 1.

```text
process 1 exited with status 42
user: ring 3 entered by iretq, exit(42) through SYSCALL gave status 42
```
Program 0 called `exit(42)`. `Proc::Process::finishCurrent` printed the first line, `Tests::User::run` the second after `wait` returned 42.

```text
process 2 exited with status 0
user: SYSCALL returned -ENOSYS by SYSRET with every other register intact
```
Program 1 loaded patterns into 12 registers, called an unknown system call, and checked `-38` and that nothing else changed.

```text
process 3 exited with status 7
user: 7 timer ticks passed while it ran in ring 3 and every one returned by iretq
```
Program 2 counted down 2^27 in ring 3. The number of ticks varies (a few). Each timer interrupt entered the kernel on `TSS.RSP0` and came back by `iretq`.

```text
hello from a ring 3 test program
hello from a ring 3 test program
process 4 exited with status 0
user: write, getpid, sched_yield, nanosleep, -ENOSYS, -EFAULT, -EBADF and -EINVAL behave as on Linux
```
Program 3 wrote its message twice, once to descriptor 1 and once to descriptor 2 (both go to the console), and checked every system call and error value. Doc 15.

```text
process 5 faulted: #PF Page Fault at rip 0x0000000000400000, error 0x0000000000000006, address 0x0000000000000000
process 5 killed, status 139
```
Program 4 wrote to address 0. Error code `0x6` is write (bit 1) and user (bit 2) with the page not present (bit 0 clear). Status 139 is 128 + 11, SIGSEGV. `Trap::Exception::killUserProcess` printed the first line. Doc 04.

```text
process 6 faulted: #GP General Protection Fault at rip 0x0000000000400000, error 0x0000000000000000
process 6 killed, status 139
process 7 faulted: #GP General Protection Fault at rip 0x0000000000400000, error 0x0000000000000000
process 7 killed, status 139
```
Programs 5 and 6 ran `hlt` and `cli` at their first byte. Both are privileged, so ring 3 gets a general protection fault.

```text
process 8 faulted: #UD Invalid Opcode at rip 0x0000000000400000
process 8 killed, status 132
```
Program 7 ran `ud2`. #UD has no error code, so none is printed. 132 is 128 + 4, SIGILL.

```text
process 9 faulted: #PF Page Fault at rip 0x000000000040000a, error 0x0000000000000005, address 0xffff800000000000
process 9 killed, status 139
```
Program 8 read kernel memory. The address is mapped, but without the user bit. Error `0x5` is user (bit 2) and protection violation (bit 0). `rip` is `0x40000a` because the load follows a 10-byte `mov`.

```text
process 10 faulted: #GP General Protection Fault at rip 0x0000000000400006, error 0x0000000000000000
process 10 killed, status 139
```
Program 9 executed `out dx, al` to port `0x3F8`. The TSS has no I/O permission bitmap, so ring 3 may not touch any port.

```text
process 11 faulted: #PF Page Fault at rip 0x0000000000400007, error 0x0000000000000007, address 0x0000000000400007
process 11 killed, status 139
```
Program 10 wrote to its own code page. Error `0x7` is write, user and protection violation. The page is read and execute, so the write fails.

```text
process 12 faulted: #PF Page Fault at rip 0x00007fffffffeff8, error 0x0000000000000015, address 0x00007fffffffeff8
process 12 killed, status 139
```
Program 11 jumped to its stack. The stack pointer starts at the stack top minus 8, `0x7FFFFFFFEFF8`. Error `0x15` is instruction fetch (bit 4), user (bit 2) and protection violation (bit 0): the stack is no-execute.

```text
process 13 faulted: #DE Divide Error at rip 0x0000000000400009
process 13 killed, status 136
```
Program 12 divided by zero. 136 is 128 + 8, SIGFPE.

```text
user: isolation ok, a null write, hlt, cli, ud2, a kernel read, port I/O, a write to code, a jump to the stack and a divide by zero each killed only their process
```
`Tests::User::runIsolation` checked that all nine statuses were right and that the PMM free count did not change.

### The ELF program

```text
elf: PT_LOAD 0x0000000000400000 file 1682 mem 1682 r-x
elf: PT_LOAD 0x0000000000401000 file 167 mem 167 r--
elf: PT_LOAD 0x0000000000402000 file 8 mem 16 rw-
elf: 3 segments, 3 pages, entry 0x0000000000400000, stack top 0x00007ffffffff000
```
`Proc::Process::startElf` loaded `hello.elf`. One line per segment: address, bytes copied from the file, bytes in memory, permissions. The data segment has 8 file bytes and 16 memory bytes, so the last 8 are zero (`.bss`). The last line is the summary. Doc 15.

```text
hello from user mode, pid 14
data 42, bss 0 then 1
write(1, 0x1, 5) = -14
write(7, ...) = -9
syscall 9999 = -38
sleep(0.05 s) = 0
yield() = 0
goodbye from user mode
process 14 exited with status 0
user: hello from a static ELF64 module loaded by Limine ran and exited with status 0
```
The output of `user/hello/src/main.ign`. It is process 14, after the 13 test programs. `data 42` shows `.data` was loaded (41 plus 1), `bss 0 then 1` shows `.bss` was zeroed. The three negative results are `-EFAULT`, `-EBADF` and `-ENOSYS`.

### The terminal

```text
keyboard: PS/2, scancode set 1, US layout, IRQ1 through the IOAPIC
```
`Drivers::Keyboard::initialize` configured the 8042 and enabled the first port. The keyboard interrupt, routed earlier, is now live.

```text
> 
```
`Shell::Terminal::run` printed the prompt and sleeps in `sti; hlt` until a key arrives. Everything after this line in a real run is what you type. `make keytest` types a fixed sequence here and checks the echo.
