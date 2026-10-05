/* Pieces of GDT setup that Ignis inline asm cannot express: a far return to
 * reload CS, and the statically allocated stack for the double fault IST. */

.intel_syntax noprefix

.section .text

/* void ignis_gdt_reload_segments(u16 code, u16 data)
 *
 * Reloads CS through a far return, then the data segment registers. */
.global ignis_gdt_reload_segments
ignis_gdt_reload_segments:
    movzx rdi, di
    push rdi
    lea rax, [rip + 1f]
    push rax
    retfq
1:
    mov ds, si
    mov es, si
    mov ss, si
    xor eax, eax
    mov fs, ax
    mov gs, ax
    ret

/* u64 ignis_double_fault_stack_top(void) */
.global ignis_double_fault_stack_top
ignis_double_fault_stack_top:
    lea rax, [rip + double_fault_stack_end]
    ret

.section .bss

.balign 16
double_fault_stack:
    .skip 16384
double_fault_stack_end:

.section .note.GNU-stack,"",@progbits
