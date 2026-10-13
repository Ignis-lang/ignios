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
| 16 | x87 and SSE state | 17 | SMEP, SMAP and fault probes |
| 18 | Per-CPU data and `swapgs` | 19 | Files: initramfs, VFS and descriptors |
| 20 | Memory mappings: `mmap` and a user heap | 21 | The native IgniOS ABI |
| 22 | Processes from user space and the shell | 23 | The process lifecycle: parents, waiting and killing |
| 24 | Locks: spinlocks, ranks, wait queues and mutexes | | |

## The subsystems

Each subsystem is a directory under `kernel/src/` with a `mod.ign` facade. The facade declares the namespace (`export namespace Mm {}`) and imports the files that add to it, the same way `std/libc` does. `ignis.toml` has one alias per subsystem, so another subsystem writes `import Mm from "@mm"` and never imports a file inside the directory. A file that no import reaches is not compiled, even when assembly refers to its `@externName` symbols, which is why every file is listed in its facade.

| Directory | Namespace | Alias | Imports | Owns |
|---|---|---|---|---|
| `lib/` | `Lib` | `@lib` | nothing | `Mem`, `Format`, `ScancodeQueue` |
| `arch/` | `Arch` | `@arch` | nothing | `Cpu`, `Port`, `Gdt`, `Idt`, `Pic`, `Pit`, `Context`, `UserMode`, `InterruptFrame`, `Spin`, all `.S` files |
| `boot/` | `Boot` | `@boot` | nothing | `Limine`, `Hhdm` |
| `drivers/` | `Drivers` | `@drivers` | Arch, Boot, Lib | `Serial`, `Console`, `Color`, `Font`, `Ps2`, `Keyboard` |
| `acpi/` | `Acpi` | `@acpi` | Boot, Drivers | `Rsdp`, `Xsdt`, `Madt`, `Fadt`, `Table` |
| `mm/` | `Mm` | `@mm` | Arch, Boot, Drivers, Lib | `Pmm`, `Vmm`, `AddressSpace`, `Heap`, `Modules` |
| `fs/` | `Fs` | `@fs` | Drivers, Lib, Mm | `Tar`, `Initramfs`, `Vfs`, `Files` |
| `apic/` | `Apic` | `@apic` | Acpi, Arch, Drivers, Mm | `Lapic`, `Ioapic` |
| `time/` | `Time` | `@time` | Apic, Arch, Drivers | `Timer` |
| `sched/` | `Sched` | `@sched` | Arch, Mm, Time | `Thread`, `Scheduler`, `Wait`, `Mutex` |
| `proc/` | `Proc` | `@proc` | Arch, Boot, Drivers, Fs, Lib, Mm, Sched | `Process`, `Elf`, `Programs`, `Memory` |
| `power/` | `Power` | `@power` | Acpi, Arch, Drivers | power off and reset |
| `syscall/` | `Syscall` | `@syscall` | Arch, Drivers, Fs, Lib, Mm, Power, Proc, Sched, Time | `Operation`, `Core`, `Linux`, `Native` |
| `trap/` | `Trap` | `@trap` | Apic, Arch, Drivers, Proc, Sched, Time | `Exception`, `Setup`, the dispatcher |
| `shell/` | `Shell` | `@shell` | Arch, Drivers, Lib, Proc, Sched, Time | `Terminal`, `Commands`, `ThreadCommands` |
| `tests/` | `Tests` | `@tests` | Arch, Boot, Drivers, Fs, Lib, Mm, Proc, Sched, Time, Trap | the boot self-tests |

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
| 6 | ACPI, APIC, the timer and power | `acpi/*.ign`, `power/mod.ign`, `arch/x86_64/pic.ign`, `apic/lapic.ign`, `apic/ioapic.ign`, `arch/x86_64/pit.ign`, `time/timer.ign` |
| 7 | Keyboard | `drivers/ps2.ign`, `lib/scancode_queue.ign`, `drivers/keyboard.ign`, `drivers/tty.ign` |
| 8 | Threads, scheduling, locks and the shell | `arch/x86_64/context.ign`, `context_asm.S`, `sched/thread.ign`, `sched/scheduler.ign`, `arch/x86_64/spinlock.ign`, `sched/sync.ign`, `shell/*.ign` |
| 9 | User mode | `arch/x86_64/usermode.ign`, `usermode_asm.S`, `proc/process.ign`, `syscall/*.ign`, `proc/elf.ign`, `mm/modules.ign`, `proc/programs.ign`, `user/` |
| 10 | Files | `initramfs/`, `fs/tar.ign`, `fs/initramfs.ign`, `fs/vfs.ign`, `fs/files.ign`, `syscall/linux/files.ign`, `user/fstest/`, `user/cat/`, `user/ls/`, `user/touch/`, `user/mkdir/` |
| 11 | Boot self-tests | `tests/*.ign`, `arch/x86_64/user_test_asm.S` |
| 12 | Scripts | `scripts/` |

All paths are under `kernel/src/` unless they say otherwise. The assembly files and the architecture code are in `kernel/src/arch/x86_64/`.

---

## Part 1. Build and boot

Read these first. They define what the kernel is made of and how it gets the machine. Concept docs 01 and 02.

**`Makefile`.** The header comment draws the build pipeline. Ignis compiles all of `kernel/src/**/*.ign` to one C file, clang compiles it, clang assembles the `.S` files, `ld.lld` links them with `kernel/linker.ld`, and `mtools` puts the result in a FAT32 disk image. Look at `QEMU_FLAGS` (q35 machine, the `max` CPU model so SMEP and SMAP exist, OVMF firmware as two flash drives, `-no-reboot`) and at the `run-headless` target, which is the quickest way to see a boot. It checks the banner, the prompt and the i64 minimum line that `hello` prints. One thing to know: the link order of the `.S` objects follows the order of `find`, so the layout of `build/kernel.elf` can differ between checkouts.

**`ignis.toml`.** The Ignis project file. `std = false` means no standard library. The `cflags` comment explains each clang flag (no red zone, no SSE, kernel code model, no stack protector). The kernel never uses SSE, user programs may: `user/hello/ignis.toml` leaves it on. Doc 02.

**`kernel/linker.ld`.** Puts the kernel at `0xffffffff80000000` in three segments (text, rodata, data) with the page-aligned boundary symbols `__text_start` and so on. The table in the header shows the layout. `Mm::Vmm::mapKernelImage` uses these symbols to map each segment with its own permissions. Doc 01.

**`boot/limine.conf`.** The Limine configuration: the kernel path and the only module, the initramfs archive with the user programs in `/bin`. Doc 01.

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

**`arch/x86_64/cpu.ign`.** Short wrappers for `cli`, `sti`, `hlt`, `rdmsr`, `wrmsr`, `cpuid` and control registers. `saveAndDisableInterrupts` and `restoreInterrupts` are the kernel's only mutual exclusion: with one processor, interrupts off means nothing else runs. Doc 02.

**`arch/x86_64/gdt.ign` and `gdt_asm.S`.** The GDT has five entries and the TSS descriptor. The header decodes every descriptor value bit by bit and draws the TSS. The selector order (kernel code, kernel data, user data, user code) is the order `SYSCALL` and `SYSRET` need. `gdt_asm.S` reloads `CS` with a far return, because `CS` cannot be loaded with `mov`. Doc 03.

**`arch/x86_64/idt.ign`.** The 256-entry table. The header draws the 16-byte gate and explains the attribute byte `0x8E`. Only 50 gates are filled (vectors 0 to 48 and the APIC spurious vector 255). Doc 04.

**`arch/x86_64/interrupt_asm.S`.** One thunk per vector, then one common stub. The header draws what the stack looks like when the dispatcher runs, which is the `Arch::InterruptFrame` record of `interrupt_frame.ign`. Notice that the thunk pushes a dummy error code for the vectors where the CPU pushes none, so the frame has one shape. Doc 04.

**`trap/dispatch.ign`, `trap/exception.ign` and `trap/setup.ign`.** `Trap::dispatch` is the one place every vector arrives. The header diagram shows the routing. `exception.ign` has the table of exceptions: read `killUserProcess` and `isUserFault` for the rule that a fault in ring 3 kills the process and a fault in ring 0 halts the machine. `setup.ign` has the boot steps that install the GDT, the IDT, the x87 and SSE units, SMEP and SMAP and the `SYSCALL` registers and log what they did. `dispatch` starts with `clac`, because an interrupt from ring 3 keeps the user's AC flag, counts the entries that came with AC set so `Tests::User` can prove the `clac` works, and asks `Arch::Probe::recover` before it treats a ring 0 fault as fatal. Doc 04.

**`arch/x86_64/fpu.ign`.** Turns on the x87 and SSE units (CR0 and CR4 bits in the header table) and saves and restores them with `fxsave64` and `fxrstor64`. The scheduler calls `save` and `restore` on every switch, so each thread has its own vector and floating point registers. The header explains why the switch is eager and not lazy. Doc 16.

**`arch/x86_64/protection.ign`, `probe.ign` and `probe_asm.S`.** SMEP and SMAP: ring 0 may not run or touch user pages. `allowUserAccess` and `forbidUserAccess` (`stac` and `clac`) open and close the window for code that has to read a user address directly. The probes are the two places where a ring 0 fault is not fatal: `Arch::Probe::recover` moves the saved RIP past the fault, which is how the self-test checks that SMEP and SMAP fault. Doc 17.

## Part 5. Memory

Read in this order: `hhdm`, `pmm`, `vmm`, `heap`, `address_space`. Each uses the one before. `mm/modules.ign` comes with part 9.

**`boot/hhdm.ign`.** Physical address `p` is at `offset + p` in the higher half direct map. Two functions. Doc 09.

**`mm/pmm.ign`.** The frame allocator, a bitmap with one bit per 4 KiB frame. The header shows how a bit maps to a frame number and an address, and where the bitmap itself is placed. A second bitmap marks the frames the allocator manages, so freeing a frame that was never usable panics instead of adding firmware or kernel memory to the free list. `allocateLargeFrame` hands out 2 MiB aligned runs of 512 frames. Frame 0 is never handed out so address 0 can mean "no frame". Doc 08.

**`mm/vmm.ign`.** The page tables. This is the longest explanation in the tree. The header shows the address split (9+9+9+9+12 bits), the page table entry bits, the PAT memory types and the virtual address space map. `initialize` has the numbered order of operations. The `*In` functions work on any PML4, which is what lets the same code build a process address space. Doc 09.

**`mm/heap.ign`.** A first-fit allocator over a region that grows on demand. The header draws the 16-byte block header, the address-ordered free list, how an aligned request splits a block and how a free merges neighbours. The compiler's allocation handlers (`onAllocate` and `onFree`) at the end of the namespace are what escaping closures use. Doc 10.

**`mm/address_space.ign`.** One PML4 per process. The lower half is private and the upper half is a copy of the kernel's 256 entries, so kernel mappings made later still show up in every process. The user-pointer functions (`copyFromUser` and the others) translate through the process page tables instead of dereferencing a user address, which is why SMAP costs the kernel nothing. A process may also hold 2 MiB pages (`mapLargePage`), and `destroy` frees them as their 512 frames. Doc 14.

## Part 6. ACPI, APIC and the timer

Docs 05 and 12.

**`acpi/mod.ign`, `rsdp.ign`, `xsdt.ign`, `madt.ign`, `table.ign`.** Finds the MADT through the RSDP and the XSDT. `mod.ign` draws the walk, `rsdp.ign` and `table.ign` show the structure layouts, `xsdt.ign` searches the root table by signature and `madt.ign` parses the interrupt controller entries. The parser reads every field byte by byte because the tables are packed. Only the local APIC address, the IOAPICs and the interrupt source overrides are kept.

**`arch/x86_64/pic.ign`.** The legacy 8259. The kernel remaps it to vectors `0x20` to `0x2F` and masks every line. The table in the header lists the four initialization words. It stays remapped so a spurious interrupt lands on a known vector.

**`apic/lapic.ign`.** The local APIC. Look at the register table and the LVT entry layout. `initialize` maps the page uncached, enables the APIC through the spurious vector register and sets LINT0 masked and LINT1 to NMI.

**`apic/ioapic.ign`.** The IOAPIC and its redirection entries. The header shows the 64-bit entry bit by bit. `route` writes the high half before the low half, because the low write is the one that unmasks the pin.

**`arch/x86_64/pit.ign`.** The 8254 timer as a stopwatch: channel 2, mode 0, polled through port `0x61`. Used once.

**`time/timer.ign`.** Measures the APIC timer against the PIT for 50 ms, derives the initial count for 100 Hz, and starts the timer in periodic mode. The interrupt handler only increments a counter. The header shows the calibration arithmetic with the numbers from a real run.

**`acpi/fadt.ign` and `power/mod.ign`.** Turning the machine off and resetting it. `Acpi::Fadt` reads the PM1 control ports, the SMI command port and the reset register from the FADT, and finds the S5 sleep type by looking for the AML encoding of `Name (_S5_, Package {...})` in the DSDT; the header draws the bytes. `Power` puts the chipset in ACPI mode when it is not, writes `SLP_TYP` and `SLP_EN`, and resets through the FADT register or the 8042. The native `POWER` call and Linux `reboot(2)` reach them; `make powertest` checks both. `make run` boots without `-no-reboot`, so `reboot` boots again instead of ending QEMU.

## Part 7. Keyboard

Doc 06. `kmain` enables the keyboard last, but the path it uses runs through the IOAPIC route set up in part 6.

**`drivers/ps2.ign`.** The 8042 controller. The header gives the status bits and the configuration byte. `handleInterrupt` runs in the IRQ1 handler and moves bytes into the queue.

**`lib/scancode_queue.ign`.** A single-producer single-consumer ring buffer between the interrupt handler and the terminal. There is no lock. Each side writes only its own index, and every access is volatile.

**`drivers/keyboard.ign`.** The scancode set 1 decoder with a US layout. The header lists the make codes and draws the state machine. It handles Shift, Caps Lock, Ctrl (a letter with Ctrl decodes to its control code, Ctrl+D to 4), the `0xE0` prefix and the six-byte Pause sequence. `Drivers::Keyboard::initialize` brings the controller up and prints the keyboard line.

**`drivers/tty.ign`.** Line input, like a Unix terminal in canonical mode: echo, Backspace, Enter, and Ctrl+D for the end of input. It is the clearest example of the `cli`, check, `sti; hlt` pattern that avoids a lost wakeup: the queue is tested with interrupts off so a key cannot arrive between the test and the sleep. `readLine` serves the kernel terminal; `read` serves descriptor 0 of a program and keeps the rest of a line for the next read. Both return with the interrupt flag as they found it, because a system call must not let another process's call reuse the kernel's staging buffers halfway through.

## Part 8. Threads, scheduling and the shell

Doc 13.

**`arch/x86_64/context.ign` and `context_asm.S`.** The context switch. A thread that is not running is a saved stack pointer. The header of `context_asm.S` draws the stack of a thread that has never run, and the trampoline that starts it. A switch is an ordinary function call that pushes six registers, swaps `rsp` and pops six registers. It must run with interrupts off.

**`sched/thread.ign`.** The thread table: one slot per thread, its state and its stack, and the 512-byte x87 and SSE area of each slot. The header has the state diagram and the layout of a thread stack with its guard page.

**`sched/scheduler.ign`.** The run queue, sleeping and the timer-driven preemption. The header has the call chain from the timer interrupt to a switch. Look at how a dead thread's stack is freed by the next thread (`reapZombie`), because a thread cannot free the stack it is running on. Sleeping and waking are here and not in a file of their own, because `sleep` calls `switchToNext` and `switchToNext` calls the wake-up scan. `join` blocks a thread until another one is gone: the thread that frees the dead one (`reapZombie`) makes its waiters ready, so a waiter runs once, not once per tick. `switchToNext` also swaps the x87 and SSE state.

**`arch/x86_64/spinlock.ign` and `sched/sync.ign`.** The lock primitives, phase C1 of the concurrency proposal; no subsystem uses them yet. A spinlock takes its word with `xchg` and, while held, raises the per-CPU preemption counter (`gs:[24]`) so the timer tick defers any thread switch; `lockIrq` also turns interrupts off for data a handler touches. Every lock has a rank: a CPU takes spinlocks in rising rank order and releases them in reverse, and a violation panics, which turns a lock-order deadlock into a boot failure. `sync.ign` adds wait queues, where a thread queues itself and releases the spinlock with interrupts off so no wake-up is lost, and a mutex whose waiters sleep. Mutex ranks follow the thread, and a mutex cannot be taken while a spinlock is held. The scheduler panics when a thread yields or sleeps with a spinlock held. Doc 24.

**`shell/terminal.ign`.** Where the boot thread ends up: it runs `/bin/sh` and waits for it, and when the shell ends it becomes the kernel terminal, a prompt, a line from `Drivers::Tty::readLine`, a command.

**`shell/commands.ign` and `shell/thread_commands.ign`.** The commands: `uptime`, `ps`, `threads` and `run PROGRAM [ARG...]`. `reboot` and `shutdown` are programs in `/bin`. Any other line that is not blank runs as a program, so `cat /etc/motd` is `run cat /etc/motd`.

## Part 9. User mode

Docs 14 and 15.

**`arch/x86_64/usermode.ign` and `usermode_asm.S`.** How the CPU enters and leaves ring 3. `ignis_enter_user` builds an `iretq` frame. `initialize` programs `IA32_STAR`, `IA32_LSTAR` and `IA32_FMASK`, and the header shows the bit fields. The `SYSCALL` entry stub in `usermode_asm.S` is the most delicate code in the tree: it switches stacks by hand through the per-CPU block, builds the same frame the interrupt stub builds, and refuses to execute `SYSRET` with a non-canonical return address.

**`arch/x86_64/cpu_local.ign` and `cpu_local_asm.S`.** The per-CPU block behind the GS base. The header has the table of the two GS MSRs in ring 0 and ring 3, and the list of every place that runs `swapgs`: the `SYSCALL` entry and exit, the interrupt stub when the saved CS is ring 3, and the first entry to ring 3. Doc 18.

**`proc/process.ign`.** The process table. A process is a slot plus a kernel thread that owns the address space. The header draws the lifetime from `startElf` to `wait`, which blocks in `Sched::Scheduler::join` until the process thread is gone. Each process records its parent, and only the parent may wait for it; `releaseChildren` frees the children of a process that ends, or makes the running ones orphans that are freed when they end, so no slot stays taken. `waitAny` parks the caller (`Sched::Scheduler::park`) until a child ends and `wakeParent` wakes it. `kill` marks a process and wakes it from a sleep, a wait or a keyboard read (`Sched::Scheduler::interrupt`, `Drivers::Tty::cancel`); `checkKill`, at the end of every system call and every interrupt from ring 3, ends it with status 137, so a process never dies in the middle of kernel code. The table holds 64 processes; the descriptor and region tables of each grow on the heap.

**`syscall/dispatch.ign`, `operation.ign` and `linux/`.** Two-step dispatch: the call number maps to an operation through a per-process table, then the operation runs. `dispatch.ign` draws the flow, `operation.ign` has the ABI independent operations, `linux/table.ign` lists the calls, `linux/files.ign` (part 10) and `linux/nanosleep.ign` are the handlers, and `linux/errno.ign` turns the status codes of `Fs` into errno values. `native/` is the second ABI, chosen by the IgniOS ELF note that `Proc::Elf::findAbi` looks for: `native/table.ign` has its call numbers, `native/status.ign` its published status codes, `native/calls.ign` the handlers, which put the status in RAX and the value in RDX; its header has the argument rules (paths as pointer and length, `ROOT` for `/`, `CURRENT` for the current directory; `SPAWN` with its arguments packed as NUL-terminated strings, which the kernel counts before it trusts them; `WAIT`), the open flags, the 32-byte info record and the directory entry layout. `core.ign` moves bytes for both ABIs with the user pointers checked, so they cannot drift apart. Doc 21. Every user pointer goes through `Mm::AddressSpace::copyFromUser`, `copyToUser` or `copyStringFromUser`, and a bad one is `-EFAULT`.

**`proc/elf.ign`.** The ELF64 loader. The header maps the segments of `build/user/hello.elf` to user addresses and shows the header structures. It refuses a segment that is both writable and executable.

**`mm/modules.ign` and `proc/programs.ign`.** `Mm::Modules` maps the Limine modules and finds one by its configuration string; the only one is the initramfs. `Proc::Programs::run` splits a command line into arguments, looks the program up in the file tree (`/bin/NAME` for a name without a slash) and starts it. `Proc::Process::buildStack` writes the Linux initial stack: argc, argv, an empty envp, the auxiliary vector and the strings, with the diagram in its comment.

**`proc/memory.ign` and `syscall/linux/memory.ign`.** `mmap` and `munmap`. `Proc::Memory` keeps a heap table of regions per process that grows from 32 to 1024 entries, hands out addresses downwards from `0x7F0000000000`, allocates and zeroes every page at `mmap` time, and turns the protection into page table bits (W for write, NX unless execute, nothing mapped for `PROT_NONE`). `unmap` trims or splits regions and frees their pages; it never touches the ELF image or the stack. The Linux side checks the arguments (the header has the table), copies a file for a private file mapping, and refuses `MAP_SHARED`, `MAP_FIXED` and write with execute. `user/mmtest` checks all of it from ring 3. Doc 20.

**`user/lib/common/alloc.ign`.** `std::alloc`, the heap of user programs: first-fit over 64 KiB arenas from `mmap`, an address-ordered free list that merges neighbours, and a mapping of its own for a block over 16 KiB, given back with `munmap`. It also defines the compiler's `@allocHandler` and `@freeHandler`, so closures that capture values work in a program that imports it. The header draws both block layouts.

**`user/lib/native/` and `user/nativetest/`.** The native flavour of the library, which `hello`, `cat`, `ls`, `touch` and `mkdir` use; `fstest` and `mmtest` stay on the Linux flavour so both ABIs keep a ring 3 test. `start.S` carries the IgniOS note (a section that `user/user.ld` places at the start of rodata and in a `PT_NOTE` segment) and ends the program with the native `EXIT`. `sys.ign` returns a `Sys::Result` (status, value) from the raw calls and the same portable `i64` functions as the Linux flavour, so `io` and `args` build against both. `nativetest` checks the convention from ring 3.

**`user/`.** The user side. `lib/linux/start.S` is `_start`, the entry point of every program: it reads argc and argv from the initial stack and calls the program's `main`, because a compiled function cannot start on a stack that holds no return address. `lib/linux/sys.ign` wraps the `syscall` instruction and offers a portable layer (`Sys::FileInfo`, `info`, `infoAt`, `readEntry`) over the Linux structures, `lib/common/io.ign` prints, `lib/common/args.ign` reads argv, `lib/common/panic.ign` is the `@panicHandler` every program imports with `import _ from "std::panic"` (a freestanding program without one does not compile), and `hello/src/main.ign` is the first program. `user/user.ld` places programs at `0x400000`.

## Part 10. Files

Doc 19.

**`initramfs/` and the `$(INITRAMFS)` rule of the `Makefile`.** The files the kernel boots with. The Makefile copies `initramfs/` and the user programs (in `/bin`) to `build/initramfs/` and packs that directory as a ustar archive with fixed owner, group and times, so the archive depends only on the files. `boot/limine.conf` loads it as the module `initramfs`.

**`fs/tar.ign`.** The ustar reader. The header has the block layout and the table of header fields. `next` reads one member and checks everything before it trusts it: the checksum, the magic, the octal numbers, that the data lies inside the archive, and the member type. Look at `normalize`, which turns `./a/./b//c/` into `a/b/c` and refuses a `..` component, so an archive cannot name a file outside its tree.

**`fs/initramfs.ign`.** Finds the module, walks every member once and refuses to boot if one is malformed. Later readers can then trust the archive. The data is never copied: it stays where Limine loaded it.

**`fs/vfs.ign`.** The file tree. Every file and directory is a `Fs::Node` on the heap, and a directory keeps its children in a linked list in creation order. The header has the path rules (`.`, `..`, repeated and trailing slashes, the `NAME_MAX` and `PATH_MAX` limits) and the table of status codes with the Linux error each one becomes. Files are limited to 64 MiB (`MAX_FILE_SIZE`, `-EFBIG` past it), checked before anything is allocated. Look at `seedEntry`, which builds the tree from the archive without copying file data, and at `reserve`, which copies a seeded file to the heap the first time it is written (copy on write), so the read-only archive is never touched. The VFS has no locks: its callers run with interrupts off on the only processor.

**`fs/files.ign`.** Descriptors and open files. The header draws a descriptor table: descriptors 0, 1 and 2 of a new process share one console open file, and an open file is freed with its last descriptor. The flags and status codes are this module's own, not Linux's, so another ABI can use the same functions. `Proc::Process::launch` calls `openStandard` and `finishCurrent` calls `closeAll`. `remove` deletes a file or an empty directory by path, and refuses one that a descriptor has open (`BUSY`): an open file holds a pointer to its node, so the node must outlive it. Each table also keeps the process's current directory, where relative paths start; a current directory counts as open too. `Fs::Vfs::pathOf` turns a node back into its absolute path for `getcwd`.

**`syscall/linux/files.ign`.** The Linux side: `read`, `write`, `openat`, `close`, `lseek`, `fstat`, `newfstatat`, `getdents64`, `mkdirat`, `unlinkat`, `chdir` and `getcwd`. The header has the `openat` flag table and the byte layouts of `struct stat` and `struct linux_dirent64`. Each handler checks the user pointer first, copies paths with `Mm::AddressSpace::copyStringFromUser`, translates the Linux flags to `Fs::Files` flags, and turns the status it gets back into an errno with `errorFor` (`linux/errno.ign`). `AT_FDCWD` is the process's current directory, which `chdir` changes and `getcwd` reports.

**`user/fstest/`.** A ring 3 program that checks each call and each error the way a Linux program sees them, and exits with the number of the first check that failed. The table in its header lists the checks.

**`user/sh/`.** The shell, a native program: a loop that prints `> `, reads a line from descriptor 0, splits it into words, runs the built-ins `cd` and `exit`, and starts anything else with `SPAWN` and `WAIT`. The header lists what it does and its limits (no quotes, pipes or redirections).

**`user/cat/`, `user/ls/`, `user/touch/`, `user/mkdir/`, `user/rm/`, `user/rmdir/` and `user/pwd/`.** The commands, each one a short Ignis program on `std::sys`. Each header has a table of what it does in each case and the exact error line, in the format of GNU coreutils (`ls: cannot access '/nope': No such file or directory`). `cat` maps a regular file with `mmap` and writes it out, 64 KiB per call at most, and falls back to `read` for anything else; with no argument it copies the keyboard until Ctrl+D; `ls` lists with `Sys::readEntry`, which hides `.` and `..`; `touch` opens with `O_CREAT | O_RDONLY` and takes `-EISDIR` (an existing directory) as success, as GNU touch does. `Sys::errorText` in `user/lib/linux/sys.ign` is their `strerror`.

## Part 11. Boot self-tests

**`tests/`.** One file per check, run by `kmain` where the subsystem is ready. Each prints one line and panics on the first violation, so a boot that continues has passed it. The tests use only the public functions of the subsystems. `pmm.ign`, `vmm.ign`, `heap.ign`, `address_space.ign`, `timer.ign` and `context.ign` check the primitives, `initramfs.ign` feeds the ustar reader one malformed header per error code, `vfs.ign` walks the path rules and every status code of the file tree, `user.ign` also runs `/bin/fstest`, `/bin/mmtest` with its four forbidden accesses, and the programs `run` must refuse, `address_space.ign` including a 2 MiB user page. `protection.ign` checks that SMAP and SMEP fault. `scheduler.ign` runs round-robin order, sleeping, a full table, one address space per thread and preemption of threads that never yield. `locks.ign` checks the spinlock, the preemption counter, lock ranks, wait queues and the mutex, each against the bug it guards. `user.ign` and `arch/x86_64/user_test_asm.S` hold sixteen throwaway ring 3 programs. Seven behave (exit, registers, spin, a spin with RFLAGS.AC set, system calls, the x87 and SSE check that runs as two processes, and a 200 ms nap that `wait` must block on) and nine do something forbidden. The kernel must kill each of the nine with the right status. `cpu_local.ign` runs last and checks that every way in and out of ring 3 left the GS bases balanced.

## Part 12. Scripts

**`scripts/keytest.sh`, `scripts/shelltest.sh`, `scripts/powertest.sh` and `scripts/screenshot.sh`.** Boot QEMU headless, wait for the prompt on the serial log, and drive the QEMU monitor (`sendkey`, `screendump`). `keytest.sh` also checks the echo, and that each typed line ran as a program. `shelltest.sh` types one command at a time, waits for the next prompt, and compares what each command printed, line for line, with the session in the script; an entry can type more lines after its command, and Ctrl+D, for a program that reads the keyboard. `powertest.sh` runs QEMU without `-no-reboot`, types `reboot`, waits for the second boot, types `shutdown`, and requires QEMU to exit by itself. **`scripts/gen-font.py`** regenerates `drivers/font_8x16.ign` from the Spleen BDF file. **`flake.nix`** provides the toolchain.

---

## Virtual address space map

Paging is set up in `mm/vmm.ign`. The kernel uses one PML4 entry per region so the regions cannot collide. See doc 09.

```text
0x0000000000000000  ┌──────────────────────────────────────────┐
                    │ page 0: never mapped (null pointers)     │
0x0000000000400000  ├──────────────────────────────────────────┤
                    │ user program: text, rodata, data, bss    │  PML4 0..255
                    │ (from the ELF, one region per segment)   │  private to each
0x0000100000000000  ├──────────────────────────────────────────┤  process
                    │ mmap regions, handed out downwards from  │
                    │ 0x00007F0000000000 (Proc::Memory)        │
0x00007FFFFFFF7000  ├──────────────────────────────────────────┤
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

Physical memory is not drawn because it depends on the machine. `Mm::Pmm` takes it from the Limine memory map: only `usable` regions are handed out, frame 0 is never handed out, and the two bitmaps sit in the first usable region at or above 1 MiB that is large enough.

## Three paths worth tracing

Follow each one with the code open. They connect the parts above.

| Path | Steps |
|---|---|
| A key press | keyboard, 8042, IRQ1, IOAPIC pin 1, vector `0x21`, `interrupt_asm.S` thunk 33, `Trap::dispatch`, `Drivers::Ps2::handleInterrupt`, `Lib::ScancodeQueue::push`, `Apic::Lapic::endOfInterrupt`. Later `Shell::Terminal::run` pops the byte and `Drivers::Keyboard::decode` turns it into a character. |
| A preemption | LAPIC timer, vector `0x30`, `Trap::dispatch`, `Time::Timer::handleTick`, `Apic::Lapic::endOfInterrupt`, `Sched::Scheduler::onTick`, `switchToNext`, `Arch::Context::switchTo`, `ignis_switch_context`. The other thread returns from its own `switchTo` and finishes its own interrupt. |
| A system call | `syscall` in ring 3, `ignis_syscall_entry` (`swapgs`, the kernel stack from `gs:[8]`), `Syscall::dispatch`, `Syscall::Linux::write`, `Mm::AddressSpace::copyFromUser`, `Drivers::Console::writeChar`, `swapgs`, `sysretq`. |

## The boot log, line by line

This is the serial log of `make run-headless` (`build/serial.log`) on the QEMU q35 machine with the `max` CPU model, OVMF and 256 MiB of RAM. Values such as addresses, tick counts and the number of switches vary between runs and machines, and the explanation says when a value is fixed by the code. "Serial only" marks lines that `kmain` writes to COM1 before the console exists or deliberately not to the screen. Every other line is on the screen too.

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

```text
fpu: x87 and SSE enabled, control bits 0x0000000000000602, 512-byte FXSAVE area per thread, saved on every switch
```
`Trap::Setup::initializeFpu`. `0x602` combines CR0.MP (`0x2`) with CR4.OSFXSR (`0x200`) and CR4.OSXMMEXCPT (`0x400`); CR0.EM and CR0.TS are clear. The initial x87 and SSE state every thread starts from was saved right after. Doc 16.

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
memory map: 35 entries, hhdm offset 0xffff800000000000
```
`Mm::Pmm::reportMemoryMap`. The Limine memory map has 35 entries (the firmware's layout, which depends on the CPU model). `0xffff800000000000` is where physical address 0 appears in virtual memory (the direct map). Doc 08.

### Memory

```text
pmm: 53469 usable frames, 53465 free (208 MiB)
```
`Mm::Pmm::initialize` counted 53469 usable 4 KiB frames, and `Mm::Pmm::report` printed the line. Four are already taken: they hold the two bitmaps, used and managed (2 x 1024 words of 8 bytes = 16 KiB = 4 frames). The size in MiB is `free * 4 / 1024` with integer division. Doc 08.

```text
pmm: self-test ok
```
`Tests::Pmm::run` allocated and freed 8 frames and checked alignment, uniqueness, the free count and reuse, and that `isAllocated` is false for the kernel image's first physical frame (from Limine, since the VMM is not up yet), which was never usable.

```text
vmm: cr3 switched, cr3 0x0000000000001000, pml4 0x0000000000001000
```
`Mm::Vmm::initialize` built the kernel page tables and loaded CR3, and `Mm::Vmm::report` printed the line. The PML4 is at physical address `0x1000`, which is frame 1: the lowest free frame, since frame 0 is never handed out. Both numbers are the same because `Mm::Vmm::rootTable` is the CR3 value. Doc 09.

```text
vmm: self-test ok
```
`Tests::Vmm::run` mapped a frame at a test address, wrote through it, read it through the direct map, and unmapped it.

```text
modules: initramfs is /initramfs.tar, 204800 bytes at 0xffff80000a09c000
```
The Limine module from `boot/limine.conf`. `initramfs` is the `module_string`, `/initramfs.tar` the path. `Mm::Modules::initialize` mapped its pages read only. The address is in the direct map, so the file sits at physical `0xa09c000`. Doc 15.

```text
heap: self-test ok, 1092 KiB mapped, 0 bytes in use
```
`Tests::Heap::run` checked alignment, reuse, merging, growth (it allocates 1 MiB) and the compiler allocation handlers. 1092 KiB of heap pages stayed mapped and every block was freed. Doc 10.

```text
initramfs: 204800 bytes, 15 files with 191563 bytes of data, 3 directories
initramfs: self-test ok, 6 malformed headers refused, 2 valid ones read, etc/motd read back
```
`Fs::Initramfs::initialize` walked the archive: `etc/motd` and the fourteen programs in `bin` (`cat`, `fstest`, `hello`, `ls`, `mkdir`, `mmtest`, `nativetest`, `pwd`, `reboot`, `rm`, `rmdir`, `sh`, `shutdown`, `touch`) are the files, and `.`, `bin` and `etc` the directories. The size is a multiple of 10240 bytes because tar pads the archive to whole records. `Tests::Initramfs::run` then fed the reader one broken header per error code (checksum, magic, a non-octal number, a `..` path, a symbolic link, data past the end), a file and a directory with a prefix, and compared `etc/motd` with the text it should hold.

```text
vfs: 20 nodes, 191563 bytes in files, seeded from the initramfs
vfs: self-test ok, lookup, create, read, write, truncate, remove and copy on write
```
`Fs::Vfs::initialize` built the tree: the root, `bin` with its fourteen programs, `etc` and `etc/motd` from the archive, then `dev` and the device node `dev/console`. The file bytes are the same 191563 as in the archive, because nothing was copied. `Tests::Vfs::run` checked every path rule, created, wrote, read, truncated and removed a test directory `/t` and checked that the heap returned to where it was, then wrote to `/etc/motd` to check that the write copied the file and left the archive alone.

```text
address space: self-test ok, private user half, shared kernel half, frames returned
```
`Tests::AddressSpace::run` created two spaces, checked that the lower half is private and the upper half shared (including a mapping made after the spaces existed), switched CR3 between them, mapped a 2 MiB user page in a third space, and destroyed them all without leaking frames. Doc 14.

```text
protection: smep on, smap on
protection: self-test ok, a ring 0 read of a user page faulted and worked inside stac/clac, a ring 0 call into a user page faulted
```
`Trap::Setup::initializeProtection` set CR4.SMEP and CR4.SMAP, which CPUID leaf 7 reports on this CPU model ("not supported" otherwise). `Tests::Protection::run` mapped one user page and probed it from ring 0: the read faulted with error `0x1`, the same read between `stac` and `clac` worked, and the call faulted with error `0x11` (instruction fetch). Doc 17.

```text
usermode: syscall enabled, star 0x0010000800000000, lstar 0xffffffff80012dff, fmask 0x0000000000044700
```
Serial only. `Trap::Setup::initializeUserMode` called `Arch::UserMode::initialize`, which pointed the GS base at the per-CPU block (doc 18), set `EFER.SCE` and wrote three MSRs. `star` is `(0x10 << 48) | (0x08 << 32)`: `SYSCALL` loads CS `0x08`, `SYSRET` loads CS `0x23` and SS `0x1B`. `lstar` is the address of the entry stub and changes with every build. `fmask` `0x44700` is the flags `SYSCALL` clears: TF, IF, DF, NT and AC. Doc 14.

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
acpi: power off through PM1a port 0x0000000000000604 with S5 sleep type 0, reset through port 0x0000000000000cf9 value 15
```
`Acpi::Fadt::read` found the FADT and, in the DSDT, the `\_S5` package. Powering off writes sleep type 0 with `SLP_EN` to the PM1a control port `0x604` (`Power::powerOff`). Resetting writes `0x0F` to `0xCF9`, the reset control register of the q35 chipset that the FADT names (`Power::reset`). The `shutdown` and `reboot` programs use them.

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
timer: calibrated on PIT channel 2: 62605844 Hz (divide 16), initial count 626058, 100 Hz periodic, vector 0x0000000000000030
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
locks: spinlock self-test ok, interrupts restored, 3 switches deferred while a lock was held, no lost update, rank order enforced
locks: mutex and wait queue self-test ok, a contender slept until the holder was done, three waiters woke together and a kill did not wake them
```
`Sched::Scheduler::enablePreemption` was called, then `Tests::Scheduler::runPreemptive`. The timer took the processor away from spinning threads at least twice (the number varies).
`Tests::Locks::run` then checked the lock primitives. It held a spinlock across more than a time slice while a helper thread wanted the processor: no switch happened, three ticks deferred theirs, and a switch followed the release. Three workers incremented a counter under a spinlock, each read-to-write section longer than a time slice, and the total came out right. A mutex contender slept until its holder, sleeping with the mutex, was done; three threads queued on a wait queue ignored a kill-style interrupt and all woke on `wakeAll`. Doc 24.

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
user: 8 timer ticks passed while it ran in ring 3 and every one returned by iretq
```
Program 2 counted down 2^27 in ring 3. The number of ticks varies (a few). Each timer interrupt entered the kernel on `TSS.RSP0` and came back by `iretq`.

```text
process 4 exited with status 0
user: 18 interrupts from ring 3 with RFLAGS.AC set ran their handlers with AC clear
```
`Tests::User::runAccessFlag` ran program 15. It set RFLAGS.AC with `popfq` and counted down 2^27 so timer interrupts arrived while AC was set. `Trap::dispatch` starts with `clac` and counts, for each entry, whether the saved RFLAGS from ring 3 had AC set and whether AC is still set after the `clac`. The first count must be at least one, the second must stay 0, and the program exits with 0 only if `iretq` gave it AC back. The number varies. Without the `clac`, a user program could run every interrupt handler with SMAP off. Doc 17.

```text
hello from a ring 3 test program
hello from a ring 3 test program
process 5 exited with status 0
user: write, getpid, sched_yield, nanosleep, -ENOSYS, -EFAULT, -EBADF and -EINVAL behave as on Linux
```
Program 3 wrote its message twice, once to descriptor 1 and once to descriptor 2 (both go to the console), and checked every system call and error value. Doc 15.

```text
process 6 exited with status 0
process 7 exited with status 0
user: two processes kept their own xmm0-xmm15, MXCSR and x87 control word across 50 yields and 6 preemptions
```
`Tests::User::runFpu` started program 13 twice. Each copy loaded a pattern made from its pid into the sixteen XMM registers, the MXCSR rounding bits and the x87 control word, yielded to the other 50 times and checked everything after each yield, then spun 2^29 times so the timer had to preempt it, and checked again. The number of preemptions varies, and the test requires at least one. Doc 16.

```text
process 8 exited with status 42
process 9 exited with status 5
user: wait blocked until the process was gone, 6 switches for a 200 ms process, none for one that had already ended
```
`Tests::User::runWait`. Program 0 and then program 14 were started. Program 14 slept 200 ms (20 ticks) with `nanosleep` and exited with 5. Waiting for it cost a handful of switches, where waking once per tick would cost about 40. Program 0 was ahead in the run queue, so it had already ended and been cleaned up by then, and the wait for it returned 42 without blocking. Doc 13.

```text
process 10 faulted: #PF Page Fault at rip 0x0000000000400000, error 0x0000000000000006, address 0x0000000000000000
process 10 killed, status 139
```
Program 4 wrote to address 0. Error code `0x6` is write (bit 1) and user (bit 2) with the page not present (bit 0 clear). Status 139 is 128 + 11, SIGSEGV. `Trap::Exception::killUserProcess` printed the first line. Doc 04.

```text
process 11 faulted: #GP General Protection Fault at rip 0x0000000000400000, error 0x0000000000000000
process 11 killed, status 139
process 12 faulted: #GP General Protection Fault at rip 0x0000000000400000, error 0x0000000000000000
process 12 killed, status 139
```
Programs 5 and 6 ran `hlt` and `cli` at their first byte. Both are privileged, so ring 3 gets a general protection fault.

```text
process 13 faulted: #UD Invalid Opcode at rip 0x0000000000400000
process 13 killed, status 132
```
Program 7 ran `ud2`. #UD has no error code, so none is printed. 132 is 128 + 4, SIGILL.

```text
process 14 faulted: #PF Page Fault at rip 0x000000000040000a, error 0x0000000000000005, address 0xffff800000000000
process 14 killed, status 139
```
Program 8 read kernel memory. The address is mapped, but without the user bit. Error `0x5` is user (bit 2) and protection violation (bit 0). `rip` is `0x40000a` because the load follows a 10-byte `mov`.

```text
process 15 faulted: #GP General Protection Fault at rip 0x0000000000400006, error 0x0000000000000000
process 15 killed, status 139
```
Program 9 executed `out dx, al` to port `0x3F8`. The TSS has no I/O permission bitmap, so ring 3 may not touch any port.

```text
process 16 faulted: #PF Page Fault at rip 0x0000000000400007, error 0x0000000000000007, address 0x0000000000400007
process 16 killed, status 139
```
Program 10 wrote to its own code page. Error `0x7` is write, user and protection violation. The page is read and execute, so the write fails.

```text
process 17 faulted: #PF Page Fault at rip 0x00007fffffffeff8, error 0x0000000000000015, address 0x00007fffffffeff8
process 17 killed, status 139
```
Program 11 jumped to its stack. The stack pointer starts at the stack top minus 8, `0x7FFFFFFFEFF8`. Error `0x15` is instruction fetch (bit 4), user (bit 2) and protection violation (bit 0): the stack is no-execute.

```text
process 18 faulted: #DE Divide Error at rip 0x0000000000400009
process 18 killed, status 136
```
Program 12 divided by zero. 136 is 128 + 8, SIGFPE.

```text
user: isolation ok, a null write, hlt, cli, ud2, a kernel read, port I/O, a write to code, a jump to the stack and a divide by zero each killed only their process
```
`Tests::User::runIsolation` checked that all nine statuses were right and that the PMM free count did not change.

### The ELF program

```text
elf: PT_LOAD 0x0000000000400000 file 2354 mem 2354 r-x
elf: PT_LOAD 0x0000000000401000 file 211 mem 211 r--
elf: PT_LOAD 0x0000000000402000 file 8 mem 16 rw-
elf: 3 segments, 3 pages, entry 0x0000000000400000, stack pointer 0x00007fffffffef90, argc 3, abi native
```
`Tests::User::runHello` ran the line `hello one two`, so `Proc::Programs::run` looked up `/bin/hello` in the file tree and `Proc::Process::startElf` loaded it. One line per segment: address, bytes copied from the file, bytes in memory, permissions. The data segment has 8 file bytes and 16 memory bytes, so the last 8 are zero (`.bss`). The last line is the summary. The entry is `_start` of `user/lib/native/start.S`, linked first; its IgniOS note made the loader pick the native ABI (`abi native`). The stack pointer is the address of argc: the 14 bytes of `hello\0one\0two\0` rounded up to 16 below the top, then 12 words (argc, three argv entries, two zeros, three auxiliary pairs), rounded down to 16. Doc 15.

```text
argv: hello one two
hello from user mode, pid 19
data 42, bss 0 then 1
i64 minimum = -9223372036854775808
write(1, 0x1, 5) = -13
write(7, ...) = -10
syscall 9999 = -14
sleep(0.05 s) = 0
yield() = 0
goodbye from user mode
process 19 exited with status 0
user: /bin/hello from the initramfs ran with 3 arguments and exited with status 0
```
The output of `user/hello/src/main.ign`. The first line is argv as `main` received it from `_start`; `make run-headless` checks it. It is process 19, after the 18 test processes. `data 42` shows `.data` was loaded (41 plus 1), `bss 0 then 1` shows `.bss` was zeroed. The i64 minimum line shows that `Io::printNumber` negates in `u64`, where -2^63 has a magnitude; `make run-headless` fails if it is wrong. The three negative results are native status codes, negated by the portable `Sys` functions: `BAD_ADDRESS` (13), `BAD_DESCRIPTOR` (10) and `NOT_SUPPORTED` (14). A Linux program would see `-EFAULT`, `-EBADF` and `-ENOSYS` (-14, -9, -38) from the same mistakes.

```text
run: /bin/nope: no such file or directory
run: /etc: not a regular file
elf: the file is smaller than an ELF header
run: no program given
elf: too many arguments
user: run refused a missing program, a directory, a file that is not ELF, an empty line and 33 arguments
```
`Tests::User::runRefused` asked `run` for a program that does not exist, a directory, `/etc/motd` (a text file the ELF loader refuses), a line of spaces and 33 arguments, one more than `MAX_ARGUMENTS`. None started a process, and the PMM free count and the heap were the same afterwards.

```text
elf: PT_LOAD 0x0000000000400000 file 9010 mem 9010 r-x
elf: PT_LOAD 0x0000000000403000 file 403 mem 403 r--
elf: PT_LOAD 0x0000000000404000 file 0 mem 4753 rw-
elf: 3 segments, 6 pages, entry 0x0000000000400000, stack pointer 0x00007fffffffefa0, argc 1, abi linux
fstest: openat, read, write, lseek, close, fstat, newfstatat, getdents64 and mkdirat behave as on Linux
process 20 exited with status 0
user: fstest passed, and removing /fstest gave back every byte it used
```
`Tests::User::runFiles` ran `/bin/fstest` (`user/fstest/src/main.ign`). Its data segment has no file bytes and 4753 bytes of memory: it is all `.bss`, the buffers of the checks. The program went through every file system call from ring 3: `openat` of `/etc/motd` gave descriptor 3, the first one after the console's 0, 1 and 2; reads, seeks, `fstat`; every `openat` error; `mkdirat` of `/fstest`; creating, appending and truncating `/fstest/a`; a path relative to a directory descriptor; `getdents64` (`.`, `..`, `a`, `b`); the limit of 256 descriptors (the table grows from 16); and the console as a character device. Its exit status would have named the first check that failed. The test then removed `/fstest` with `Fs::Vfs::remove` and checked that the heap and the PMM were back where they were before the program started. Doc 15.

```text
Welcome to IgniOS.
mmtest: anonymous and file mappings, protection, munmap, their errors and std::alloc behave as expected
process 21 exited with status 0
process 22 faulted: #PF Page Fault at rip 0x0000000000400325, error 0x0000000000000007, address 0x00007efffffff000
process 22 killed, status 139
process 23 faulted: #PF Page Fault at rip 0x00000000004004cf, error 0x0000000000000004, address 0x00007efffffff000
process 23 killed, status 139
process 24 faulted: #PF Page Fault at rip 0x00007efffffff000, error 0x0000000000000015, address 0x00007efffffff000
process 24 killed, status 139
process 25 faulted: #PF Page Fault at rip 0x0000000000400542, error 0x0000000000000004, address 0x00007efffffff000
process 25 killed, status 139
panic: alloc: free of a pointer that is not a live block at alloc.ign:112
process 26 exited with status 101
user: mmtest passed, writing read-only, using unmapped, executing non-exec and touching PROT_NONE memory were killed, a double free was caught, no frame leaked
```
`Tests::User::runMemory` ran `/bin/mmtest` (the loader's `elf:` lines left out). The first line is `/etc/motd`, which the program read into a mapping and wrote from it, to show that system calls take mapped memory as a buffer. The checks also mapped `/etc/motd` and a page of `/bin/hello` privately, and ran `std::alloc` through 200 blocks, a large block and a closure. Then the program ran four more times with an argument, each one doing something the page tables must stop, and each one was killed. Every first mapping of a process is the page below `0x7F0000000000`, `0x7EFFFFFFF000`. The error codes say why: `0x7` is a write to a present read-only user page, `0x4` a user read of a page that is not present (unmapped, or `PROT_NONE`, which maps nothing), `0x15` an instruction fetch from a no-execute page; `rip` equal to the address is the jump into the mapping. The last run freed a `std::alloc` block twice; the allocator panicked, and the shared handler of `std::panic` printed the message with its file and line on standard error and exited with 101. The PMM free count was the same afterwards. Doc 20.

```text
elf: 3 segments, 6 pages, entry 0x0000000000400000, stack pointer 0x00007fffffffefa0, argc 1, abi native
nativetest: hello through the native ABI
/
process 28 exited with status 0
...
process 102 killed, status 137
process 103 killed, status 137
process 104 killed, status 137
process 105 killed, status 137
process 107 killed, status 137
nativetest: every native call, its arguments and its status codes behave as specified
process 27 exited with status 0
elf: the IgniOS ABI note names an unknown version
elf: a note runs past the end of the file
user: nativetest passed, a note of version 2 and a note past the end of the file were refused
```
`Tests::User::runNative` ran `/bin/nativetest`. Its ELF carries the IgniOS note, so the loader printed `abi native` (every other program says `abi linux`) and the process used the native call table. The program checked that a call returns its status in RAX and its value in RDX, that an error leaves RDX at 0 even when RDX went in with another value, and that call 9999 and Linux's `getpid` number 39 are both `NOT_SUPPORTED`; then every native call with its errors, in a directory `/nt` that the test removed afterwards (the table in `user/nativetest/src/main.ign` lists the checks). The lines left out (`...`) are its own children: `/bin/pwd` and `/bin/rmdir` runs for the spawn checks, 63 `pwd` children that fill the 64-slot process table, and helpers for the parent checks (an orphan and a child that ends before its parent are both freed). The five `killed, status 137` lines are the kill checks: a child sleeping 10 s, one spinning in ring 3, one waiting for the keyboard, one waiting for its own child, and one that killed itself. Each ended right away with 128 + 9. Then the test handed the loader two copies of the same file with the note broken, one claiming version 2 and one with a description larger than the file; both were refused before anything was mapped, and no memory leaked. Doc 21.

```text
cpu local: self-test ok, after ring 3 the kernel GS base is the per-CPU block and the user one is 0
```
`Tests::CpuLocal::run`, after every way in and out of ring 3 has run many times: `IA32_GS_BASE` still names the per-CPU block, a `gs:[0]` load returns the block's own address, and `IA32_KERNEL_GS_BASE`, the user's base while the kernel runs, is 0. A missing or extra `swapgs` anywhere would break this. Doc 18.

### The terminal

```text
keyboard: PS/2, scancode set 1, US layout, IRQ1 through the IOAPIC
```
`Drivers::Keyboard::initialize` configured the 8042 and enabled the first port. The keyboard interrupt, routed earlier, is now live.

```text
elf: 3 segments, 3 pages, entry 0x0000000000400000, stack pointer 0x00007fffffffefa0, argc 1, abi native
> 
```
`Shell::Terminal::run` started `/bin/sh` (the loader's line, the PT_LOAD lines left out), and the shell printed its prompt. It now waits in `Drivers::Tty`, with `sti; hlt`, until a key arrives. Everything after this line in a real run is what you type. `make keytest` types a fixed sequence here and checks the echo, and `make shelltest` types a session. A session looks like this (the loader's `elf:` lines left out):

```text
> mkdir /tmp
process 22 exited with status 0
> cd /tmp
> touch a
process 23 exited with status 0
> ls
a
process 24 exited with status 0
> cat /nope
cat: /nope: No such file or directory
process 25 exited with status 1
> nope
sh: nope: command not found
```
`sh` splits each line into words, runs `cd` and `exit` itself and starts anything else from `/bin` (or from a path) with `SPAWN`, then `WAIT`s for it; the kernel prints the `process N exited` lines. Ctrl+D or `exit` ends the shell, and the kernel terminal takes over the keyboard with its own commands (`uptime`, `ps`, `threads`, `run`). The tree lives in memory: `/tmp` is gone after a reboot.
