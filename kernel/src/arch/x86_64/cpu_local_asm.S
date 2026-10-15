/* The per-CPU block and the routines that reach it through GS.
 *
 * The blocks, one per processor, 64 bytes each, MAX_CPUS (8) of them:
 *
 *   gs:[0]   self          the block's own address, so code can turn the
 *                          GS-relative block into an ordinary pointer
 *   gs:[8]   kernel rsp    top of the kernel stack of the running thread,
 *                          the stack the SYSCALL entry switches to
 *   gs:[16]  user rsp      scratch: the user stack pointer between "syscall"
 *                          and the push that saves it in the frame
 *   gs:[24]  preempt count above 0 while this CPU holds a spinlock
 *   gs:[32]  spin top      the highest rank of the spinlocks it holds
 *   gs:[40]  cpu index     the processor's number, 0 for the boot processor
 *
 * These offsets are used by usermode_asm.S too. Arch::CpuLocal::initialize
 * points IA32_GS_BASE at the block and sets IA32_KERNEL_GS_BASE to 0. See
 * concept doc 18. */

.intel_syntax noprefix

.set CPU_LOCAL_SELF, 0
.set CPU_LOCAL_KERNEL_RSP, 8

.section .text

/* u64 ignis_cpu_local_address(void): the address of the first block; block
 * n is 64 * n bytes further. */
.global ignis_cpu_local_address
ignis_cpu_local_address:
    lea rax, [rip + ignis_cpu_local]
    ret

/* u64 ignis_cpu_local_self(void): gs:[0], the self pointer read through GS. */
.global ignis_cpu_local_self
ignis_cpu_local_self:
    mov rax, gs:[CPU_LOCAL_SELF]
    ret

/* void ignis_set_syscall_kernel_stack(u64 top): gs:[8] = top, the stack the
 * next SYSCALL runs on. Runs in ring 0, so GS is the kernel's. */
.global ignis_set_syscall_kernel_stack
ignis_set_syscall_kernel_stack:
    mov gs:[CPU_LOCAL_KERNEL_RSP], rdi
    ret

.section .bss

.balign 64
ignis_cpu_local:
    .skip 64 * 8

.section .note.GNU-stack,"",@progbits
