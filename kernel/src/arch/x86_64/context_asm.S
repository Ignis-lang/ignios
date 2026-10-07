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
 * RSP+8 is 16-byte aligned, as the ABI requires at function entry.
 *
 * Stack of a thread that is switched out, the same six registers in the order
 * ignis_switch_context pushes them (the pushes run from rbp down to r15, so
 * r15 ends up at the lowest address, which is the saved RSP):
 *
 *   saved RSP ->  r15
 *                 r14
 *                 r13
 *                 r12
 *                 rbx
 *                 rbp
 *                 return address: the instruction after the "call" to
 *                                 ignis_switch_context in Context::switchTo
 *
 * Both shapes are the same, which is why a new thread can be resumed by the
 * same code that resumes a thread that was switched out. See concept doc 13. */

.intel_syntax noprefix

.section .text

/* void ignis_switch_context(u64 *save_rsp, u64 next_rsp)
 *
 * rdi = address where the outgoing RSP is stored, rsi = RSP of the incoming
 * context. Returns, on the incoming stack, to whoever switched that context
 * out (or into the trampoline for a new thread). */
.global ignis_switch_context
ignis_switch_context:
    /* Save the callee-saved registers on the outgoing stack. */
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15

    /* The switch itself: record where the outgoing stack ends, then adopt the
     * incoming one. From the next instruction on this code runs on the
     * incoming thread's stack. */
    mov [rdi], rsp
    mov rsp, rsi

    /* Restore the incoming context's registers and resume it. */
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
    /* Scheduler::threadBegin: frees the stack of the thread that died just
     * before this one was switched in, if any. Needs interrupts off. */
    call ignis_thread_begin

    /* From here the thread is an ordinary one. */
    sti

    /* First argument of the thread function: the value prepareStack stored. */
    mov rdi, r13
    call r12

    /* The thread function returned: end the thread. It never returns, and
     * ud2 makes sure a bug there faults loudly. */
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
