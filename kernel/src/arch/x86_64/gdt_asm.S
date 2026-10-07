/* The one piece of GDT setup that Ignis inline asm cannot express: reloading
 * CS. The kernel GDT itself, the TSS and its stack for the double fault live
 * in gdt.ign.
 *
 * Why this needs assembly: "lgdt" only loads the table register. The segment
 * registers keep the descriptor they cached from the bootloader's GDT until
 * they are loaded again. DS, ES, SS, FS and GS can be loaded with "mov", but
 * CS cannot: it changes only through a far jump, a far call or a far return.
 * The far return below pops a new RIP and CS from the stack. */

.intel_syntax noprefix

.section .text

/* void ignis_gdt_reload_segments(u16 code, u16 data)
 *
 * Reloads CS through a far return, then the data segment registers.
 * System V ABI arguments: di = code selector, si = data selector. It runs
 * with interrupts off: Arch::Gdt::initialize is called that way, from
 * Trap::Setup::initializeGdt.
 *
 * Stack at the "retfq":
 *
 *   rsp ->  return RIP  (the label "1:" below)   popped first
 *           new CS      (the code selector)      popped second
 */
.global ignis_gdt_reload_segments
ignis_gdt_reload_segments:
    /* Zero-extend the selector to a full stack word. */
    movzx rdi, di
    push rdi

    /* The address to continue at: the instruction after "retfq". */
    lea rax, [rip + 1f]
    push rax

    /* Far return, 64-bit operand size: pops RIP, then CS. */
    retfq
1:
    /* CS is now the new code segment. Load the data selector into DS, ES and
     * SS. In 64-bit mode their base and limit are ignored, but the selector
     * must still name a valid data descriptor. */
    mov ds, si
    mov es, si
    mov ss, si

    /* FS and GS get the null selector. The kernel does not use them. */
    xor eax, eax
    mov fs, ax
    mov gs, ax
    ret

.section .note.GNU-stack,"",@progbits
