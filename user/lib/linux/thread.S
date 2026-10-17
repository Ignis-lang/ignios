/* The assembly half of the thread module (thread.ign) of the Linux flavour.
 *
 *   i64 ignis_thread_clone(u64 flags, u64 stack, u64 parent_tid,
 *                          u64 child_tid, u64 tls)
 *
 * Calls `clone` (Linux number 56) with the arguments in the Linux x86_64
 * order: rdi flags, rsi stack, rdx parent_tid, r10 child_tid, r8 tls. The
 * parent gets the child's tid or -errno back and returns normally.
 *
 * The child resumes after the same `syscall` with the parent's registers,
 * RAX 0 and RSP `stack`. It must not return: the parent's frame is not on its
 * stack. The caller leaves two words at `stack`, which is 16-byte aligned:
 *
 *   stack + 0     the address of the thread function, u64 function(u64)
 *   stack + 8     its argument
 *
 * The child pops both, which leaves RSP 16-byte aligned as a `call` expects,
 * clears RBP (the end of the frame-pointer chain), calls the function and
 * passes its result to `exit` (Linux number 60), which ends this thread only.
 *
 *   u64 ignis_thread_function_address(u64 (*function)(u64))
 *
 * Ignis cannot turn a function into an integer, and an extern function only
 * takes a function named at the call site, so a thread function is converted
 * there. */

.intel_syntax noprefix

.section .text

.global ignis_thread_clone
ignis_thread_clone:
    mov r10, rcx            /* child_tid: syscall overwrites rcx */
    mov eax, 56             /* clone */
    syscall
    test rax, rax
    jnz 1f                  /* the parent: a tid or -errno */
    xor ebp, ebp
    pop rax                 /* the function */
    pop rdi                 /* its argument */
    call rax
    mov rdi, rax            /* exit(result) */
    mov eax, 60
    syscall
    ud2                     /* exit does not return */
1:
    ret

.global ignis_thread_function_address
ignis_thread_function_address:
    mov rax, rdi
    ret

.section .note.GNU-stack,"",@progbits
