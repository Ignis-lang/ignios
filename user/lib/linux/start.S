/* The entry point of every IgniOS user program, `_start`.
 *
 * The kernel starts a program the way Linux starts a static executable: RSP
 * points at argc and is 16-byte aligned, and no return address was pushed.
 * The initial stack (built by Proc::Process::buildStack in the kernel):
 *
 *   rsp + 0          argc
 *   rsp + 8          argv[0] ... argv[argc - 1]   pointers to NUL-terminated strings
 *   ...              0                            end of argv
 *   ...              0                            end of envp (no environment yet)
 *   ...              auxv pairs (type, value), ending with AT_NULL (0, 0)
 *   higher           the argument strings
 *
 * A compiled function expects RSP + 8 to be 16-byte aligned at its first
 * instruction, as if a `call` had just pushed a return address, so `_start`
 * cannot be one. This stub reads argc and argv, clears RBP (the end of the
 * frame-pointer chain), aligns the stack and calls the program:
 *
 *   u64 ignis_main(u64 argc, u64 *argv)    System V: rdi, rsi, result in rax
 *
 * and passes the result to exit_group (Linux number 231), which ends every
 * thread of the process; exit (60) would end only the calling thread. ignis_main is the program's
 * `main`, exported with @externName("ignis_main"). */

.intel_syntax noprefix

.section .text

.global _start
_start:
    xor ebp, ebp
    mov rdi, [rsp]          /* argc */
    lea rsi, [rsp + 8]      /* argv */
    and rsp, -16            /* already aligned by the kernel; kept for safety */
    call ignis_main
    mov rdi, rax            /* exit_group(status) */
    mov eax, 231
    syscall
    ud2                     /* exit_group does not return */

.section .note.GNU-stack,"",@progbits
