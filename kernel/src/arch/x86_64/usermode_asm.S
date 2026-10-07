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
 * kernel stack from "gs:" and saves the user GS base on the way out. */

.intel_syntax noprefix

.section .text

/* void ignis_enter_user(u64 rip, u64 rsp)
 *
 * Leaves ring 0 for good through an iretq frame: SS, RSP, RFLAGS with IF set,
 * CS, RIP. Every general register is zeroed first so no kernel value leaks to
 * the program. Called with interrupts off, on the thread's kernel stack, which
 * TSS.RSP0 already names; the frames above it are abandoned. */
.global ignis_enter_user
ignis_enter_user:
    cli
    push 0x1B
    push rsi
    push 0x202
    push 0x23
    push rdi

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
    mov [rip + ignis_syscall_user_rsp], rsp
    mov rsp, [rip + ignis_syscall_kernel_rsp]

    push 0x1B
    push qword ptr [rip + ignis_syscall_user_rsp]
    push r11
    push 0x23
    push rcx
    push 0
    push 256

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
    call ignis_syscall_dispatch

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

    /* rsp -> rip, cs, rflags, user rsp, ss. Canonical means bits 63:47 all
     * equal: shifting left by 16 and arithmetic right by 16 gives the same
     * value back. */
    mov rcx, [rsp]
    mov r11, rcx
    shl r11, 16
    sar r11, 16
    cmp r11, rcx
    jne 1f

    mov r11, [rsp + 16]
    mov rsp, [rsp + 24]
    sysretq

1:
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

/* u64 ignis_syscall_entry_address(void) */
.global ignis_syscall_entry_address
ignis_syscall_entry_address:
    lea rax, [rip + ignis_syscall_entry]
    ret

.section .bss

.balign 8
ignis_syscall_user_rsp:
    .skip 8
ignis_syscall_kernel_rsp:
    .skip 8

.section .note.GNU-stack,"",@progbits
