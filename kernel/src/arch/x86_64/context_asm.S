/* Kernel stack switching.
 *
 * A thread that is not running is just a stack whose top holds the registers
 * ignis_switch_context saved, then the address it will return to. Switching
 * pushes the callee-saved registers of the System V AMD64 ABI (rbx, rbp,
 * r12-r15) on the old stack, stores RSP, loads the new RSP, pops the same six
 * registers and returns. The caller-saved registers need no saving: the
 * switch is an ordinary function call, so the compiler already assumes they
 * are lost across it.
 *
 * Invariant: ignis_switch_context must be called with interrupts disabled.
 * An interrupt between "mov [rdi], rsp" and "mov rsp, rsi" would run on a
 * stack that no thread owns yet and push its frame on the old thread's stack
 * after that thread's RSP was recorded.
 *
 * Stack of a thread that never ran, lowest address first, T being the
 * 16-byte aligned end of its stack:
 *
 *   T-56  r15
 *   T-48  r14
 *   T-40  r13  argument for the thread function
 *   T-32  r12  address of the thread function
 *   T-24  rbx
 *   T-16  rbp  0, which ends frame-pointer walks
 *   T- 8  return address: ignis_thread_trampoline
 *
 * The first switch pops six registers and returns into the trampoline with
 * RSP == T. The trampoline is reached by "ret", not by "call", so it is not
 * a function entry: its "call r12" is the call that matters. That call pushes
 * the return address, so the thread function starts with RSP == T-8 and
 * RSP+8 is 16-byte aligned, as the ABI requires at function entry. */

.intel_syntax noprefix

.section .text

/* void ignis_switch_context(u64 *save_rsp, u64 next_rsp) */
.global ignis_switch_context
ignis_switch_context:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov [rdi], rsp
    mov rsp, rsi

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

/* Where the first switch into a new thread lands. r12 holds the thread
 * function and r13 its argument. Interrupts are off until the "sti": the
 * switch that got here ran with them disabled. */
ignis_thread_trampoline:
    call ignis_thread_begin
    sti
    mov rdi, r13
    call r12
    call ignis_thread_exit
    ud2

/* u64 ignis_thread_trampoline_address(void) */
.global ignis_thread_trampoline_address
ignis_thread_trampoline_address:
    lea rax, [rip + ignis_thread_trampoline]
    ret

/* u64 ignis_function_address(void (*function)(u64))
 *
 * Ignis cannot forward a function value to an extern function, and cannot
 * turn one into an integer, so a thread entry is converted at the call site
 * that names the function. */
.global ignis_function_address
ignis_function_address:
    mov rax, rdi
    ret

.section .note.GNU-stack,"",@progbits
