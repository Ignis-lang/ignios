/* Ring 3 entry and the SYSCALL entry stub.
 *
 * Selectors, with the RPL of ring 3 in the low two bits:
 *   0x08 kernel code, 0x10 kernel data, 0x18|3 user data, 0x20|3 user code.
 * IA32_STAR holds 0x08 for SYSCALL (SS = 0x10) and 0x10 for SYSRET, which
 * loads SS = 0x10 + 8 = 0x18|3 and CS = 0x10 + 16 = 0x20|3 in 64-bit mode.
 *
 * Interrupts and exceptions taken in ring 3 are saved by the common stub in
 * interrupt_asm.S on the stack TSS.RSP0 names. SYSCALL does not switch
 * stacks, so the entry stub below does it by hand, with two slots that
 * ignis_set_syscall_kernel_stack and the stub use. The kernel has one CPU, so
 * a plain global is enough. With several CPUs this becomes per-CPU data
 * reached through the GS base: the stub starts with "swapgs", loads the
 * kernel stack from "gs:" and saves the user GS base on the way out.
 *
 * The SYSCALL and SYSRET instructions (Intel SDM Vol. 2B, "SYSCALL" and
 * "SYSRET"):
 *
 *   SYSCALL   RCX <- RIP of the next instruction
 *             R11 <- RFLAGS
 *             RFLAGS <- RFLAGS & ~IA32_FMASK
 *             CS <- IA32_STAR[47:32], SS <- that + 8, CPL 0
 *             RIP <- IA32_LSTAR
 *             RSP is NOT changed: it still holds the user stack pointer.
 *
 *   SYSRETQ   RIP <- RCX
 *             RFLAGS <- R11
 *             CS <- IA32_STAR[63:48] + 16, SS <- IA32_STAR[63:48] + 8, CPL 3
 *             RSP is NOT changed: the stub must load the user stack first.
 *
 * See concept doc 14. */

.intel_syntax noprefix

.section .text

/* void ignis_enter_user(u64 rip, u64 rsp)
 *
 * Leaves ring 0 for good through an iretq frame: SS, RSP, RFLAGS with IF set,
 * CS, RIP. Every general register is zeroed first so no kernel value leaks to
 * the program. Called with interrupts off, on the thread's kernel stack, which
 * TSS.RSP0 already names; the frames above it are abandoned.
 *
 * rdi = user entry point, rsi = user stack pointer.
 *
 * The iretq frame built on the kernel stack (lowest address first, which is
 * the order iretq pops it):
 *
 *   rsp ->  rip      user entry point       rdi
 *           cs       0x23   user code, RPL 3
 *           rflags   0x202  IF (bit 9) set, plus the always-one bit 1
 *           rsp      user stack pointer     rsi
 *           ss       0x1B   user data, RPL 3
 */
.global ignis_enter_user
ignis_enter_user:
    cli

    /* Build the frame, last field first (a push moves rsp down). */
    push 0x1B
    push rsi
    push 0x202
    push 0x23
    push rdi

    /* Zero every general purpose register. Writing a 32-bit register clears
     * the upper half, so "xor r32, r32" is enough and shorter. */
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx
    xor esi, esi
    xor edi, edi
    xor ebp, ebp
    xor r8d, r8d
    xor r9d, r9d
    xor r10d, r10d
    xor r11d, r11d
    xor r12d, r12d
    xor r13d, r13d
    xor r14d, r14d
    xor r15d, r15d

    /* Pops rip, cs, rflags, rsp, ss and continues in ring 3. */
    iretq

/* The SYSCALL target (IA32_LSTAR). On entry the processor has put the return
 * address in RCX, RFLAGS in R11, cleared the FMASK bits of RFLAGS (IF among
 * them) and kept RSP, the user stack pointer. Nothing is saved for us.
 *
 * The stub builds the same frame the interrupt stub does: the five-word
 * iretq frame, a zero error code, vector 256, then the 15 registers. The
 * dispatcher gets a pointer to it, writes the result into the rax slot, and
 * may change nothing else the user program can see.
 *
 * The frame, highest address first (the kernel stack top is where it starts):
 *
 *   ss        0x1B                    pushed by the stub (SYSCALL saves none)
 *   rsp       user stack pointer
 *   rflags    from R11
 *   cs        0x23
 *   rip       from RCX
 *   errorCode 0
 *   vector    256 (above any hardware vector: marks a system call)
 *   r15 ... rax
 *             ^ rsp, passed to ignis_syscall_dispatch as an InterruptFrame
 *
 * RCX and R11 hold the return address and RFLAGS, so the user's own values of
 * those two are gone: that is the Linux convention, user code declares them
 * clobbered.
 *
 * The way out is SYSRETQ when the saved RIP is canonical. On Intel
 * processors SYSRET faults in ring 0, still on the user stack pointer, when
 * RCX is non-canonical, so a user program that could steer RCX there would
 * run the fault handler on a stack it chose. A non-canonical RIP therefore
 * never reaches SYSRET: it ends the process (ignis_syscall_bad_return).
 * IRETQ is no better, it also faults in ring 0 on such a RIP. With the last
 * user page left unmapped (AddressSpace::USER_LIMIT) the case cannot arise
 * from a "syscall" instruction in the first place. */
.global ignis_syscall_entry
ignis_syscall_entry:
    /* Interrupts are off (FMASK cleared IF). Park the user rsp in a global
     * and switch to the kernel stack of the running thread. The global is
     * read again within a few instructions, before anything could run. */
    mov [rip + ignis_syscall_user_rsp], rsp
    mov rsp, [rip + ignis_syscall_kernel_rsp]

    /* The processor part of the frame, by hand. */
    push 0x1B
    push qword ptr [rip + ignis_syscall_user_rsp]
    push r11
    push 0x23
    push rcx
    push 0
    push 256

    /* The registers, same order as ignis_interrupt_common. */
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

    /* The ABI wants DF clear at a call. rdi = the frame. The rax slot holds
     * the call number and rdi, rsi, rdx, r10, r8, r9 the arguments. */
    cld
    mov rdi, rsp
    call ignis_syscall_dispatch

    /* Reload everything from the frame, so the result the dispatcher stored
     * in the rax slot becomes the return value. */
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

    /* Skip the vector and the error code. */
    add rsp, 16

    /* rsp -> rip, cs, rflags, user rsp, ss. Canonical means bits 63:47 all
     * equal: shifting left by 16 and arithmetic right by 16 gives the same
     * value back. */
    mov rcx, [rsp]
    mov r11, rcx
    shl r11, 16
    sar r11, 16
    cmp r11, rcx
    jne 1f

    /* Canonical: set up what SYSRETQ consumes. RCX already holds the return
     * RIP. R11 gets the saved RFLAGS, and RSP becomes the user stack pointer
     * as the very last step before the return, since the kernel stack is not
     * needed any more. */
    mov r11, [rsp + 16]
    mov rsp, [rsp + 24]
    sysretq

1:
    /* Non-canonical return address: report it and end the process, never
     * return. The call needs a 16-byte aligned rsp. */
    mov rdi, rcx
    and rsp, -16
    call ignis_syscall_bad_return
    ud2

/* void ignis_set_syscall_kernel_stack(u64 top): the stack the next SYSCALL
 * runs on, the kernel stack of the thread that is about to run. */
.global ignis_set_syscall_kernel_stack
ignis_set_syscall_kernel_stack:
    mov [rip + ignis_syscall_kernel_rsp], rdi
    ret

/* u64 ignis_syscall_entry_address(void): the value for IA32_LSTAR. */
.global ignis_syscall_entry_address
ignis_syscall_entry_address:
    lea rax, [rip + ignis_syscall_entry]
    ret

.section .bss

/* Scratch for the user stack pointer between "syscall" and the pushes. */
.balign 8
ignis_syscall_user_rsp:
    .skip 8

/* Top of the kernel stack the next "syscall" runs on. */
ignis_syscall_kernel_rsp:
    .skip 8

.section .note.GNU-stack,"",@progbits
