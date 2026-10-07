/* Interrupt entry. Every vector has a thunk that makes the stack look the
 * same whether or not the processor pushed an error code, records the vector,
 * and jumps to one common stub. The stub saves the general purpose registers
 * and calls the Ignis dispatcher with a pointer to the saved frame.
 *
 * Frame layout, lowest address first, as the Ignis InterruptFrame record
 * declares it: rax rbx rcx rdx rsi rdi rbp r8 r9 r10 r11 r12 r13 r14 r15
 * vector errorCode rip cs rflags rsp ss.
 *
 * What the stack holds while the dispatcher runs (addresses grow upward):
 *
 *   higher    ss              \
 *             rsp              |  pushed by the processor on every interrupt
 *             rflags           |  in 64-bit mode (rsp and ss even without a
 *             cs               |  privilege change)
 *             rip             /
 *             errorCode          pushed by the processor for some vectors,
 *                                otherwise a 0 pushed by the thunk
 *             vector             pushed by the thunk
 *             r15                pushed by ignis_interrupt_common, first
 *             r14
 *             ...
 *             rbx
 *   lower     rax                pushed last; rsp points here and is the
 *                                argument of ignis_interrupt_dispatch
 *
 * That is 22 eight-byte words, 176 bytes. The processor aligns rsp to 16
 * bytes before it pushes its five words, and 176 is a multiple of 16, so rsp
 * is 16-byte aligned at the "call" below, as the System V ABI requires.
 *
 * The gates are interrupt gates (type 0xE), so the processor clears RFLAGS.IF
 * on entry and the whole path runs with interrupts disabled. "iretq" restores
 * RFLAGS and with it the interrupted code's interrupt flag.
 *
 * Vectors that get a thunk: 0-31 (exceptions), 32-47 (8259 range, also the
 * IOAPIC keyboard at 33), 48 (APIC timer) and 255 (APIC spurious). Intel SDM
 * Vol. 3A, "Interrupt and Exception Handling". */

.intel_syntax noprefix

.section .text

/* THUNK vector: the entry point of one vector.
 *
 * For the vectors where the processor pushes an error code the stack is
 * already in the common shape, so only the vector number is pushed. The list
 * in the ".if" is those vectors: 8 (#DF), 10 (#TS), 11 (#NP), 12 (#SS),
 * 13 (#GP), 14 (#PF), 17 (#AC), 21 (#CP), 29 (#VC), 30 (#SX). For every other
 * vector a dummy 0 stands in for the error code. This list has to match
 * Trap::Exception::hasErrorCode. */
.macro THUNK vector
ignis_interrupt_thunk_\vector:
.if \vector != 8 && \vector != 10 && \vector != 11 && \vector != 12 && \vector != 13 && \vector != 14 && \vector != 17 && \vector != 21 && \vector != 29 && \vector != 30
    push 0
.endif
    push \vector
    jmp ignis_interrupt_common
.endm

/* Exceptions. */
.irp vector, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    THUNK \vector
.endr

/* The 8259 range, 0x20-0x2F. */
.irp vector, 32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47
    THUNK \vector
.endr

/* The local APIC timer. */
    THUNK 48

/* The local APIC spurious interrupt vector. */
    THUNK 255

/* The common stub: saves the registers, calls the dispatcher, restores them.
 * Entered by "jmp" from a thunk with [vector, errorCode, rip, cs, rflags, rsp,
 * ss] on the stack. */
ignis_interrupt_common:
    push r15
    push r14
    push r13
    push r12
    push r11
    push r10
    push r9
    push r8
    push rbp
    push rdi
    push rsi
    push rdx
    push rcx
    push rbx
    push rax

    /* The ABI requires the direction flag clear at a call. The interrupted
     * code may have had it set. */
    cld

    /* First argument: a pointer to the frame, which is the InterruptFrame. */
    mov rdi, rsp
    call ignis_interrupt_dispatch

    /* Restore in the reverse order. The dispatcher may have changed the
     * saved values (the syscall path does), and a thread switch inside it
     * means these are the registers of the thread being resumed. */
    pop rax
    pop rbx
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    pop r8
    pop r9
    pop r10
    pop r11
    pop r12
    pop r13
    pop r14
    pop r15

    /* Drop the vector and the error code so rsp points at rip, then return
     * to the interrupted code. */
    add rsp, 16
    iretq

/* u64 ignis_interrupt_thunk(u64 vector): the entry address of a vector 0-48
 * (48 is the APIC timer) or of vector 255, the local APIC spurious vector.
 * The vector comes in rdi and the address goes out in rax. Any other value
 * indexes past the table, so the caller (Arch::Idt::initialize) only passes valid
 * ones. */
.global ignis_interrupt_thunk
ignis_interrupt_thunk:
    cmp rdi, 255
    jne 1f
    lea rax, [rip + ignis_interrupt_thunk_255]
    ret
1:
    lea rax, [rip + ignis_interrupt_thunk_table]
    mov rax, [rax + rdi * 8]
    ret

.section .rodata

/* One 8-byte entry address per vector 0-48, indexed by vector. */
.balign 8
ignis_interrupt_thunk_table:
.irp vector, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    .quad ignis_interrupt_thunk_\vector
.endr
.irp vector, 32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47
    .quad ignis_interrupt_thunk_\vector
.endr
    .quad ignis_interrupt_thunk_48

.section .note.GNU-stack,"",@progbits
