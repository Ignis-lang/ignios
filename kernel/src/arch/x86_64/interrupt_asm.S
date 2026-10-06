/* Interrupt entry. Every vector has a thunk that makes the stack look the
 * same whether or not the processor pushed an error code, records the vector,
 * and jumps to one common stub. The stub saves the general purpose registers
 * and calls the Ignis dispatcher with a pointer to the saved frame.
 *
 * Frame layout, lowest address first, as the Ignis InterruptFrame record
 * declares it: rax rbx rcx rdx rsi rdi rbp r8 r9 r10 r11 r12 r13 r14 r15
 * vector errorCode rip cs rflags rsp ss. */

.intel_syntax noprefix

.section .text

.macro THUNK vector
ignis_interrupt_thunk_\vector:
.if \vector != 8 && \vector != 10 && \vector != 11 && \vector != 12 && \vector != 13 && \vector != 14 && \vector != 17 && \vector != 21 && \vector != 29 && \vector != 30
    push 0
.endif
    push \vector
    jmp ignis_interrupt_common
.endm

.irp vector, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    THUNK \vector
.endr

.irp vector, 32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47
    THUNK \vector
.endr

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

    cld
    mov rdi, rsp
    call ignis_interrupt_dispatch

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

    add rsp, 16
    iretq

/* u64 ignis_interrupt_thunk(u64 vector): the entry address of a vector 0-47. */
.global ignis_interrupt_thunk
ignis_interrupt_thunk:
    lea rax, [rip + ignis_interrupt_thunk_table]
    mov rax, [rax + rdi * 8]
    ret

.section .rodata

.balign 8
ignis_interrupt_thunk_table:
.irp vector, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    .quad ignis_interrupt_thunk_\vector
.endr
.irp vector, 32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47
    .quad ignis_interrupt_thunk_\vector
.endr

.section .note.GNU-stack,"",@progbits
