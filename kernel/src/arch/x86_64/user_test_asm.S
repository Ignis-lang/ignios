/* Throwaway ring 3 programs for the boot self-tests. Each one is
 * position-independent machine code that the kernel copies to the first user
 * page and starts at its first byte, with a fresh stack and no arguments.
 * They talk to the kernel the way a real program does, through SYSCALL with
 * Linux numbers: exit is 60, write is 1.
 *
 * Programs are listed in ignis_user_test_table as start and end address
 * pairs.
 *
 * The Linux x86_64 system call convention the programs use:
 *
 *   rax          call number (in), result or -errno (out)
 *   rdi, rsi, rdx, r10, r8, r9    arguments 1 to 6
 *   rcx, r11     destroyed by the SYSCALL instruction itself
 *   all others   preserved by the kernel
 *
 * Index  Program               Expected outcome (see kernel/src/tests/user.ign)
 *   0    exit                  exit status 42
 *   1    registers             exit status 0
 *   2    spin                  exit status 7, timer ticks arrive in ring 3
 *   3    syscalls              exit status 0
 *   4    null write            killed, SIGSEGV (139)
 *   5    hlt                   killed, SIGSEGV (139)
 *   6    cli                   killed, SIGSEGV (139)
 *   7    undefined opcode      killed, SIGILL (132)
 *   8    kernel read           killed, SIGSEGV (139)
 *   9    port output           killed, SIGSEGV (139)
 *   10   code write            killed, SIGSEGV (139)
 *   11   jump to the stack     killed, SIGSEGV (139)
 *   12   divide by zero        killed, SIGFPE (136)
 *   13   fpu                   exit status 0, run as two processes at once
 *   14   nap                   exit status 5 after sleeping 200 ms
 *   15   alignment check spin  exit status 0, timer ticks arrive with AC = 1
 *   16   clone                 exit status 0; the child thread exits with 60
 *   17   clone exit_group      exit status 77, from the child's exit_group
 *   18   futex                 exit status 0; errors, wake, join, turn stress
 *   19   futex timeout         exit status 0 after a 20 ms WAIT timed out
 *   20   futex kill            two threads asleep in WAIT; the kernel kills it */

.intel_syntax noprefix

.section .text

/* u64 ignis_user_test_start(u64 index)
 *
 * The address of program `index`. The table has two 8-byte entries per
 * program, so the byte offset is index * 16. */
.global ignis_user_test_start
ignis_user_test_start:
    lea rax, [rip + ignis_user_test_table]
    shl rdi, 4
    mov rax, [rax + rdi]
    ret

/* u64 ignis_user_test_size(u64 index)
 *
 * The length of program `index`: end address minus start address. */
.global ignis_user_test_size
ignis_user_test_size:
    lea rax, [rip + ignis_user_test_table]
    shl rdi, 4
    mov rdx, [rax + rdi + 8]
    sub rdx, [rax + rdi]
    mov rax, rdx
    ret

.section .rodata

/* Index 0: exit(42). */
user_test_exit_start:
    mov eax, 60
    mov edi, 42
    syscall
    ud2
user_test_exit_end:

/* Index 1: a system call with a number nobody implements must return
 * -ENOSYS (-38) and keep every register except RAX, RCX and R11, then the
 * program exits with status 0. Status 1 means something changed. */
.macro CHECK register, value
    mov rcx, \value
    cmp \register, rcx
    jne user_test_registers_fail
.endm

user_test_registers_start:
    /* Load a distinct pattern into every register the kernel must preserve. */
    mov rbx, 0x1111111111111111
    mov rbp, 0x2222222222222222
    mov r12, 0x3333333333333333
    mov r13, 0x4444444444444444
    mov r14, 0x5555555555555555
    mov r15, 0x6666666666666666
    mov rdx, 0x7777777777777777
    mov rsi, 0x8888888888888888
    mov rdi, 0x9999999999999999
    mov r8, 0xAAAAAAAAAAAAAAAA
    mov r9, 0xBBBBBBBBBBBBBBBB
    mov r10, 0xCCCCCCCCCCCCCCCC

    /* Call number 9999 does not exist. */
    mov eax, 9999
    syscall

    /* -ENOSYS is -38. */
    cmp rax, -38
    jne user_test_registers_fail

    /* Every pattern must have survived. rcx is the scratch of CHECK. */
    CHECK rbx, 0x1111111111111111
    CHECK rbp, 0x2222222222222222
    CHECK r12, 0x3333333333333333
    CHECK r13, 0x4444444444444444
    CHECK r14, 0x5555555555555555
    CHECK r15, 0x6666666666666666
    CHECK rdx, 0x7777777777777777
    CHECK rsi, 0x8888888888888888
    CHECK rdi, 0x9999999999999999
    CHECK r8, 0xAAAAAAAAAAAAAAAA
    CHECK r9, 0xBBBBBBBBBBBBBBBB
    CHECK r10, 0xCCCCCCCCCCCCCCCC

    /* exit(0) */
    xor edi, edi
    mov eax, 60
    syscall
    ud2
user_test_registers_fail:
    /* exit(1) */
    mov edi, 1
    mov eax, 60
    syscall
    ud2
user_test_registers_end:

/* Index 2: counts down 2^27 times in ring 3 with interrupts on, so timer
 * interrupts arrive in user mode and must come back to it, then exit(7). */
user_test_spin_start:
    mov ecx, 0x8000000
1:
    dec ecx
    jnz 1b
    mov eax, 60
    mov edi, 7
    syscall
    ud2
user_test_spin_end:

/* Index 3: the implemented system calls and their errors. The program exits
 * with status 0 when every call returned what Linux returns, and with the
 * code of the first one that did not. Output goes to the console through
 * write.
 *
 * EXPECT value, code: compares rax with the expected result. On a mismatch
 * the program exits at once with status `code`, which names the check. */
.macro EXPECT value, code
    mov rcx, \value
    cmp rax, rcx
    je 9f
    mov edi, \code
    mov eax, 60
    syscall
9:
.endm

/* The length of user_test_syscalls_message. */
.set MESSAGE_LENGTH, 33

user_test_syscalls_start:
    /* write(1, message, 33) must return 33. */
    mov eax, 1
    mov edi, 1
    lea rsi, [rip + user_test_syscalls_message]
    mov edx, MESSAGE_LENGTH
    syscall
    EXPECT MESSAGE_LENGTH, 10

    /* A bad pointer: page zero, then an address in the kernel half. */
    mov eax, 1
    mov edi, 1
    mov esi, 1
    mov edx, 5
    syscall
    EXPECT -14, 11

    mov eax, 1
    mov edi, 1
    mov rsi, 0xFFFF800000000000
    mov edx, 8
    syscall
    EXPECT -14, 12

    /* A range that starts mapped and runs off the end of the stack fails as a
     * whole and prints nothing. 0x7FFFFFFFEFFC is 4 bytes below the stack top
     * (0x7FFFFFFFF000), and 8 bytes reach into the unmapped page above. */
    mov rbx, 0x7FFFFFFFEFFC
    mov dword ptr [rbx], 0x0A646E65
    mov eax, 1
    mov edi, 1
    mov rsi, rbx
    mov edx, 8
    syscall
    EXPECT -14, 13

    /* A descriptor that is not open, and an empty write. */
    mov eax, 1
    mov edi, 7
    lea rsi, [rip + user_test_syscalls_message]
    mov edx, 1
    syscall
    EXPECT -9, 14

    mov eax, 1
    mov edi, 1
    lea rsi, [rip + user_test_syscalls_message]
    xor edx, edx
    syscall
    EXPECT 0, 15

    /* getpid must return a positive process id. */
    mov eax, 39
    syscall
    test rax, rax
    jg 1f
    mov edi, 16
    mov eax, 60
    syscall
1:
    /* sched_yield returns 0. */
    mov eax, 24
    syscall
    EXPECT 0, 17

    /* nanosleep: 20 ms, an invalid time, a bad pointer. The request is a
     * struct timespec on the stack: seconds at [rsp], nanoseconds at
     * [rsp + 8]. */
    sub rsp, 16
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 20000000
    mov eax, 35
    mov rdi, rsp
    xor esi, esi
    syscall
    EXPECT 0, 18

    /* 2e9 ns is more than one second, which is not a valid nanoseconds
     * field: -EINVAL (-22). */
    mov qword ptr [rsp + 8], 2000000000
    mov eax, 35
    mov rdi, rsp
    xor esi, esi
    syscall
    EXPECT -22, 19

    mov eax, 35
    mov edi, 1
    xor esi, esi
    syscall
    EXPECT -14, 20

    /* A call that does not exist, and write to standard error. */
    mov eax, 9999
    syscall
    EXPECT -38, 21

    mov eax, 1
    mov edi, 2
    lea rsi, [rip + user_test_syscalls_message]
    mov edx, MESSAGE_LENGTH
    syscall
    EXPECT MESSAGE_LENGTH, 22

    /* Every check passed: exit(0). */
    xor edi, edi
    mov eax, 60
    syscall
    ud2
user_test_syscalls_message:
    .ascii "hello from a ring 3 test program\n"
user_test_syscalls_message_end:
user_test_syscalls_end:


/* Indexes 4 to 12: programs that do something a user program must not. Each
 * one is killed by the kernel and the kernel keeps running. The "ud2" after
 * the offending instruction is never reached when the kernel does its job. */

/* Index 4: a write to page zero, which is never mapped. Page fault with the
 * error code 6 (write, user, not present). */
user_test_null_write_start:
    mov byte ptr [0], 1
    ud2
user_test_null_write_end:

/* Index 5: hlt, a privileged instruction. General protection fault. */
user_test_hlt_start:
    hlt
    ud2
user_test_hlt_end:

/* Index 6: cli, which needs IOPL 3. General protection fault. */
user_test_cli_start:
    cli
    ud2
user_test_cli_end:

/* Index 7: an undefined instruction. Invalid opcode fault. */
user_test_undefined_start:
    ud2
user_test_undefined_end:

/* Index 8: a read of kernel memory, mapped but without the user bit. Page
 * fault with the error code 5 (user, protection violation). */
user_test_kernel_read_start:
    mov rbx, 0xFFFF800000000000
    mov rax, [rbx]
    ud2
user_test_kernel_read_end:

/* Index 9: port input and output, which the TSS I/O permission bitmap
 * (there is none) forbids. 0x3F8 is COM1. General protection fault. */
user_test_port_start:
    mov dx, 0x3F8
    mov al, 0x58
    out dx, al
    ud2
user_test_port_end:

/* Index 10: a write to the program's own code page, which is read and
 * execute. Page fault with the error code 7 (write, user, protection). */
user_test_code_write_start:
    lea rax, [rip]
    mov byte ptr [rax], 0
    ud2
user_test_code_write_end:

/* Index 11: a jump to the stack, which is no-execute. Page fault with the
 * error code 0x15 (instruction fetch, user, protection). */
user_test_stack_jump_start:
    mov rax, rsp
    jmp rax
user_test_stack_jump_end:

/* Index 12: division by zero. Divide error. */
user_test_divide_start:
    xor edx, edx
    xor ecx, ecx
    mov eax, 1
    div ecx
    ud2
user_test_divide_end:

/* Start and end address of each program, indexed as above. */
.balign 8
/* Index 13: the x87 and SSE state of a process survives switches to other
 * processes. Two copies run at the same time. Each one derives a pattern
 * from its pid, loads it into xmm0-xmm15, the MXCSR rounding control and
 * the x87 control word, then yields 50 times and checks all of it after
 * every yield, then spins 2^29 times without yielding, so the timer has to
 * preempt it, and checks again. The other copy holds different values, so a
 * missing save or restore on either kind of switch shows up as a mismatch.
 * Exit status 0, or 1 when a value changed.
 *
 * Registers:
 *   rbx   pattern seed, pid * 0x0101010101010101; xmm i holds rbx + i in
 *         both quadwords
 *   r12   the MXCSR value: all exceptions masked (0x1F80), rounding control
 *         (bits 14:13) = pid & 3
 *   r13   the x87 control word: 0x037F, rounding control (bits 11:10) =
 *         pid & 3
 *   r14   rounds left
 *   r15   0 in the yield phase, 1 after the spin
 * The kernel preserves all five across SYSCALL. */
user_test_fpu_start:
    /* getpid */
    mov eax, 39
    syscall

    mov rbx, 0x0101010101010101
    imul rbx, rax

    mov r12, rax
    and r12, 3
    mov r13, r12
    shl r12, 13
    or r12, 0x1F80
    shl r13, 10
    or r13, 0x037F

    sub rsp, 256
    mov [rsp], r12d
    ldmxcsr [rsp]
    mov [rsp], r13w
    fldcw [rsp]

.irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    lea rcx, [rbx + \i]
    movq xmm\i, rcx
    punpcklqdq xmm\i, xmm\i
.endr

    mov r14d, 50
    xor r15d, r15d

user_test_fpu_round:
    /* sched_yield */
    mov eax, 24
    syscall

user_test_fpu_check:
    /* Store every xmm register and compare both quadwords of each. */
.irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    movdqu [rsp + 16 * \i], xmm\i
.endr

    xor ecx, ecx

user_test_fpu_compare:
    lea rdx, [rbx + rcx]
    mov rax, rcx
    shl rax, 4
    cmp [rsp + rax], rdx
    jne user_test_fpu_fail
    cmp [rsp + rax + 8], rdx
    jne user_test_fpu_fail
    inc ecx
    cmp ecx, 16
    jne user_test_fpu_compare

    stmxcsr [rsp]
    cmp [rsp], r12d
    jne user_test_fpu_fail
    fnstcw [rsp]
    cmp [rsp], r13w
    jne user_test_fpu_fail

    dec r14d
    jnz user_test_fpu_round

    /* r15d is 0 after the yield rounds and 1 after the spin. */
    test r15d, r15d
    jnz user_test_fpu_done

    /* The preemption phase: a long loop with no system call, then one more
     * check without a yield before it. */
    mov r15d, 1
    mov ecx, 0x20000000
user_test_fpu_spin:
    dec ecx
    jnz user_test_fpu_spin
    mov r14d, 1
    jmp user_test_fpu_check

user_test_fpu_done:
    /* exit(0) */
    xor edi, edi
    mov eax, 60
    syscall
    ud2

user_test_fpu_fail:
    mov edi, 1
    mov eax, 60
    syscall
    ud2
user_test_fpu_end:

/* Index 14: sleeps 200 ms (20 timer ticks) with nanosleep, then exit(5). The
 * timespec { 0 s, 200000000 ns } is built on the stack; the second argument,
 * where Linux would store the time left, is null. */
user_test_nap_start:
    sub rsp, 16
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 200000000
    mov rdi, rsp
    xor esi, esi
    mov eax, 35
    syscall
    mov edi, 5
    mov eax, 60
    syscall
    ud2
user_test_nap_end:

/* Index 15: sets RFLAGS.AC (bit 18, 0x40000), which ring 3 may change with
 * popfq, and counts down 2^27 times so timer interrupts arrive while it is
 * set. Trap::dispatch must clear AC before it runs any handler, or SMAP would
 * be off for that handler. The interrupt returns by iretq with the saved user
 * RFLAGS, so AC must still be set when the loop ends.
 *
 * Exit status: 0 when AC stayed set, 1 when popfq did not set it, 2 when it
 * was lost while the program was interrupted. AC = 1 turns on alignment
 * checking only when CR0.AM is also set, and the program makes no unaligned
 * access either way, so it cannot raise #AC. */
user_test_alignment_spin_start:
    pushfq
    or qword ptr [rsp], 0x40000
    popfq
    pushfq
    pop rax
    test eax, 0x40000
    jz user_test_alignment_spin_unset

    mov ecx, 0x8000000
1:
    dec ecx
    jnz 1b

    pushfq
    pop rax
    test eax, 0x40000
    jz user_test_alignment_spin_lost

    /* exit(0) */
    xor edi, edi
    mov eax, 60
    syscall
    ud2
user_test_alignment_spin_unset:
    /* exit(1) */
    mov edi, 1
    mov eax, 60
    syscall
    ud2
user_test_alignment_spin_lost:
    /* exit(2) */
    mov edi, 2
    mov eax, 60
    syscall
    ud2
user_test_alignment_spin_end:

/* Index 16: a thread through clone, checked from both sides. Data lives in
 * the lower of the two stack pages mapped at start (CLONE_BASE):
 *
 *   +0x00  the parent's TLS block, whose first word is its own address
 *   +0x40  the child's TLS block, the same way
 *   +0x80  parent_tid       +0x88  child_tid       +0x90  child result
 *   +0xA0  ARCH_GET_FS out  +0xA8  set_tid_address target
 *   +0xB0  the child tid the parent got            +0xB8  the child's GET_FS
 *   +0x800 the child's stack top
 *
 * The parent checks arch_prctl and the refused clone flag sets, then clones
 * with CLONE_SETTLS, CLONE_PARENT_SETTID, CLONE_CHILD_SETTID and
 * CLONE_CHILD_CLEARTID and both threads sleep 10 ms twenty times, reading
 * %fs:0 after each sleep, so each one resumes on whichever processor is
 * free and must find its own FS base there. The child checks RAX, RSP,
 * the callee-saved registers, FS, gettid and the tid words, stores 1 (or the
 * number of the failed check) at +0x90 and ends with exit(99), which ends
 * only the child. The parent then sleeps 300 ms, while the kernel test sees
 * one thread left, and ends with exit_group(0). Any other status is the
 * number of the failed check. */
.equ CLONE_BASE, 0x7FFFFFFFD000
.equ CLONE_THREAD_SET, 0x50F00
.equ CLONE_ALL_OPTIONS, 0x1380000

.macro CLONE_EXIT code
    mov edi, \code
    mov eax, 231
    syscall
.endm

/* nanosleep 10 ms with a timespec on the stack; keeps rbx, rbp, r12-r15. */
.macro CLONE_NAP
    sub rsp, 16
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 10000000
    mov rdi, rsp
    xor esi, esi
    mov eax, 35
    syscall
    add rsp, 16
.endm

user_test_clone_start:
    mov rdx, CLONE_BASE
    mov [rdx], rdx
    lea rax, [rdx + 0x40]
    mov [rdx + 0x40], rax
    xor eax, eax
    mov [rdx + 0x80], rax
    mov [rdx + 0x88], rax
    mov [rdx + 0x90], rax

    /* arch_prctl(ARCH_SET_FS, CLONE_BASE) and %fs:0 */
    mov eax, 158
    mov edi, 0x1002
    mov rsi, CLONE_BASE
    syscall
    test rax, rax
    jnz 10f
    mov rax, fs:[0]
    mov rdx, CLONE_BASE
    cmp rax, rdx
    jne 11f

    /* ARCH_GET_FS into +0xA0 */
    mov eax, 158
    mov edi, 0x1003
    lea rsi, [rdx + 0xA0]
    syscall
    test rax, rax
    jnz 12f
    mov rdx, CLONE_BASE
    cmp [rdx + 0xA0], rdx
    jne 12f

    /* a kernel address and one past the user half: -EPERM */
    mov eax, 158
    mov edi, 0x1002
    mov rsi, 0xFFFF800000000000
    syscall
    cmp rax, -1
    jne 13f
    mov eax, 158
    mov edi, 0x1002
    mov rsi, 0x0000800000000000
    syscall
    cmp rax, -1
    jne 14f

    /* an unknown code: -EINVAL; GET_FS to a kernel address: -EFAULT */
    mov eax, 158
    mov edi, 0x1001
    xor esi, esi
    syscall
    cmp rax, -22
    jne 15f
    mov eax, 158
    mov edi, 0x1003
    mov rsi, 0xFFFF800000000000
    syscall
    cmp rax, -14
    jne 16f

    /* the main thread: gettid == getpid */
    mov eax, 186
    syscall
    mov rbx, rax
    mov eax, 39
    syscall
    cmp rax, rbx
    jne 17f

    /* no CLONE_VM: -ENOSYS */
    mov eax, 56
    mov edi, CLONE_THREAD_SET & ~0x100
    xor esi, esi
    xor edx, edx
    xor r10d, r10d
    xor r8d, r8d
    syscall
    cmp rax, -38
    jne 18f

    /* CLONE_FILES missing: -EINVAL */
    mov eax, 56
    mov edi, CLONE_THREAD_SET & ~0x400
    syscall
    cmp rax, -22
    jne 19f

    /* an exit signal in the low byte: -EINVAL */
    mov eax, 56
    mov edi, CLONE_THREAD_SET | 17
    syscall
    cmp rax, -22
    jne 20f

    /* CLONE_PARENT_SETTID to a kernel address: -EFAULT */
    mov eax, 56
    mov edi, CLONE_THREAD_SET | 0x100000
    mov rdx, 0xFFFF800000000000
    syscall
    cmp rax, -14
    jne 21f

    /* set_tid_address returns the tid */
    mov eax, 218
    mov rdi, CLONE_BASE + 0xA8
    syscall
    cmp rax, rbx
    jne 22f

    /* the real clone, with a pattern in every callee-saved register */
    mov rbx, 0x1111111111111111
    mov rbp, 0x2222222222222222
    mov r12, 0x3333333333333333
    mov r13, 0x4444444444444444
    mov r14, 0x5555555555555555
    mov r15, 0x6666666666666666
    mov eax, 56
    mov edi, CLONE_THREAD_SET | CLONE_ALL_OPTIONS
    mov rsi, CLONE_BASE + 0x800
    mov rdx, CLONE_BASE + 0x80
    mov r10, CLONE_BASE + 0x88
    mov r8, CLONE_BASE + 0x40
    syscall
    test rax, rax
    jz user_test_clone_child
    js 23f

    /* the parent: the tid came back and is in parent_tid */
    mov rdx, CLONE_BASE
    mov [rdx + 0xB0], rax
    cmp [rdx + 0x80], rax
    jne 24f
    mov rbx, rax
    mov eax, 39
    syscall
    cmp rax, rbx
    je 25f

    /* sleep alongside the child, then until it reports */
    mov r12d, 20
1:
    CLONE_NAP
    mov rax, fs:[0]
    mov rdx, CLONE_BASE
    cmp rax, rdx
    jne 26f
    dec r12d
    jnz 1b
    mov r12d, 500
2:
    mov rdx, CLONE_BASE
    mov rax, [rdx + 0x90]
    test rax, rax
    jnz 3f
    CLONE_NAP
    dec r12d
    jnz 2b
    CLONE_EXIT 27
3:
    cmp rax, 1
    jne 4f

    /* the child is gone: sleep 300 ms on one thread, then end the process */
    sub rsp, 16
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 300000000
    mov rdi, rsp
    xor esi, esi
    mov eax, 35
    syscall
    add rsp, 16
    CLONE_EXIT 0
4:
    mov edi, eax
    mov eax, 231
    syscall

10: CLONE_EXIT 10
11: CLONE_EXIT 11
12: CLONE_EXIT 12
13: CLONE_EXIT 13
14: CLONE_EXIT 14
15: CLONE_EXIT 15
16: CLONE_EXIT 16
17: CLONE_EXIT 17
18: CLONE_EXIT 18
19: CLONE_EXIT 19
20: CLONE_EXIT 20
21: CLONE_EXIT 21
22: CLONE_EXIT 22
23: CLONE_EXIT 23
24: CLONE_EXIT 24
25: CLONE_EXIT 25
26: CLONE_EXIT 26

user_test_clone_child:
    mov ecx, 40
    mov rax, CLONE_BASE + 0x800
    cmp rsp, rax
    jne 5f
    mov ecx, 41
    mov rax, 0x1111111111111111
    cmp rbx, rax
    jne 5f
    mov rax, 0x2222222222222222
    cmp rbp, rax
    jne 5f
    mov rax, 0x3333333333333333
    cmp r12, rax
    jne 5f
    mov rax, 0x4444444444444444
    cmp r13, rax
    jne 5f
    mov rax, 0x5555555555555555
    cmp r14, rax
    jne 5f
    mov rax, 0x6666666666666666
    cmp r15, rax
    jne 5f

    /* its own FS base, as the MSR and as ARCH_GET_FS */
    mov ecx, 42
    mov rax, fs:[0]
    mov rdx, CLONE_BASE + 0x40
    cmp rax, rdx
    jne 5f
    mov eax, 158
    mov edi, 0x1003
    mov rsi, CLONE_BASE + 0xB8
    syscall
    mov ecx, 43
    test rax, rax
    jnz 5f
    mov rdx, CLONE_BASE
    mov rax, [rdx + 0xB8]
    lea rsi, [rdx + 0x40]
    cmp rax, rsi
    jne 5f

    /* gettid: not getpid, and in both tid words */
    mov eax, 186
    syscall
    mov rbx, rax
    mov eax, 39
    syscall
    mov ecx, 44
    cmp rax, rbx
    je 5f
    mov rdx, CLONE_BASE
    mov ecx, 45
    cmp [rdx + 0x88], rbx
    jne 5f
    mov ecx, 46
    cmp [rdx + 0x80], rbx
    jne 5f

    mov r12d, 20
6:
    CLONE_NAP
    mov ecx, 47
    mov rax, fs:[0]
    mov rdx, CLONE_BASE + 0x40
    cmp rax, rdx
    jne 5f
    dec r12d
    jnz 6b
    mov ecx, 1
5:
    mov rdx, CLONE_BASE
    mov [rdx + 0x90], rcx
    /* exit(99): only this thread */
    mov edi, 99
    mov eax, 60
    syscall
    ud2
user_test_clone_end:

/* Index 17: clone with stack 0, so the child runs on the parent's RSP; the
 * child checks that and ends the whole process with exit_group(77) while
 * the parent yields forever. 78: the child's RSP was not the parent's; 79:
 * clone failed. */
user_test_clone_group_start:
    mov r12, rsp
    mov eax, 56
    mov edi, CLONE_THREAD_SET
    xor esi, esi
    xor edx, edx
    xor r10d, r10d
    xor r8d, r8d
    syscall
    test rax, rax
    jz 2f
    js 3f
1:
    mov eax, 24
    syscall
    jmp 1b
2:
    cmp rsp, r12
    jne 4f
    CLONE_EXIT 77
3:
    CLONE_EXIT 79
4:
    CLONE_EXIT 78
user_test_clone_group_end:

/* Index 18: futex, from two threads. Data lives at FUTEX_BASE, the lower
 * of the two stack pages mapped at start:
 *
 *   +0x00  the word the first child waits on   +0x08  the child's tid word
 *   +0x10  the turn word of the stress          +0x18  the child's result
 *   +0x20  the join timeout (1 s)               +0x30  the turn timeout (2 s)
 *   +0x800 the children's stack top
 *
 * The parent checks the errors on one thread (10 to 18). A child made with
 * CLONE_CHILD_SETTID and CLONE_CHILD_CLEARTID waits on +0x00; the parent
 * wakes it, retrying every 10 ms until WAKE returns 1 (19 to 21). The child
 * records that its WAIT returned 0, stays 100 ms and ends with exit, while
 * the parent waits on the tid word until the kernel clears it (the join,
 * 30 to 32: a timeout there means the exit did not wake it). A second
 * child and the parent then take FUTEX_ROUNDS turns on +0x10, each storing
 * the other's turn and waking it, each waiting with a 2 s timeout while it
 * is not its turn: a timeout is a lost wake-up (26, or 28 from the child).
 * Status 0 when everything held. */
.equ FUTEX_BASE, 0x7FFFFFFFD000
.equ FUTEX_ROUNDS, 1000
.equ FUTEX_CLONE, CLONE_THREAD_SET | 0x1200000

user_test_futex_start:
    mov rbx, FUTEX_BASE
    xor eax, eax
    mov [rbx], rax
    mov [rbx + 0x08], rax
    mov [rbx + 0x10], rax
    mov [rbx + 0x18], rax
    mov qword ptr [rbx + 0x20], 1
    mov [rbx + 0x28], rax
    mov qword ptr [rbx + 0x30], 2
    mov [rbx + 0x38], rax

    /* an unaligned word: -EINVAL */
    lea rdi, [rbx + 1]
    xor esi, esi
    xor edx, edx
    xor r10d, r10d
    mov eax, 202
    syscall
    cmp rax, -22
    jne 10f

    /* a kernel address and an unmapped user address: -EFAULT */
    mov rdi, 0xFFFF800000000000
    xor esi, esi
    xor edx, edx
    xor r10d, r10d
    mov eax, 202
    syscall
    cmp rax, -14
    jne 11f
    mov edi, 0x10000000
    xor esi, esi
    xor edx, edx
    xor r10d, r10d
    mov eax, 202
    syscall
    cmp rax, -14
    jne 12f

    /* an op the kernel does not have (FUTEX_FD, private): -ENOSYS */
    mov rdi, rbx
    mov esi, 130
    xor edx, edx
    xor r10d, r10d
    mov eax, 202
    syscall
    cmp rax, -38
    jne 13f

    /* WAKE with nobody waiting: 0 */
    mov rdi, rbx
    mov esi, 129
    mov edx, 1
    xor r10d, r10d
    mov eax, 202
    syscall
    test rax, rax
    jnz 14f

    /* WAIT for 1 while the word is 0: -EAGAIN at once */
    mov rdi, rbx
    mov esi, 128
    mov edx, 1
    xor r10d, r10d
    mov eax, 202
    syscall
    cmp rax, -11
    jne 15f

    /* timeouts with 10^9 ns and with negative seconds: -EINVAL */
    mov qword ptr [rbx + 0x40], 0
    mov qword ptr [rbx + 0x48], 1000000000
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    lea r10, [rbx + 0x40]
    mov eax, 202
    syscall
    cmp rax, -22
    jne 16f
    mov qword ptr [rbx + 0x40], -1
    mov qword ptr [rbx + 0x48], 0
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    lea r10, [rbx + 0x40]
    mov eax, 202
    syscall
    cmp rax, -22
    jne 17f

    /* a timeout at a kernel address: -EFAULT */
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    mov r10, 0xFFFF800000000000
    mov eax, 202
    syscall
    cmp rax, -14
    jne 18f

    /* the first child waits on +0x00 */
    mov eax, 56
    mov edi, FUTEX_CLONE
    lea rsi, [rbx + 0x800]
    xor edx, edx
    lea r10, [rbx + 0x08]
    xor r8d, r8d
    syscall
    test rax, rax
    jz user_test_futex_waiter
    js 19f

    /* WAKE until it finds the child asleep */
    mov r12d, 200
1:
    mov rdi, rbx
    mov esi, 1
    mov edx, 1
    xor r10d, r10d
    mov eax, 202
    syscall
    cmp rax, 1
    je 2f
    test rax, rax
    jnz 20f
    CLONE_NAP
    dec r12d
    jnz 1b
    CLONE_EXIT 21
2:
    call user_test_futex_join
    test eax, eax
    jnz 9f
    cmp qword ptr [rbx + 0x18], 1
    jne 23f

    /* the turn stress with a second child */
    mov qword ptr [rbx + 0x18], 0
    mov eax, 56
    mov edi, FUTEX_CLONE
    lea rsi, [rbx + 0x800]
    xor edx, edx
    lea r10, [rbx + 0x08]
    xor r8d, r8d
    syscall
    test rax, rax
    jz user_test_futex_turner
    js 24f
    mov r13d, FUTEX_ROUNDS
3:
    mov edx, [rbx + 0x10]
    test edx, edx
    jz 4f
    lea rdi, [rbx + 0x10]
    mov esi, 128
    lea r10, [rbx + 0x30]
    mov eax, 202
    syscall
    cmp rax, -110
    je 26f
    jmp 3b
4:
    mov dword ptr [rbx + 0x10], 1
    lea rdi, [rbx + 0x10]
    mov esi, 129
    mov edx, 1
    xor r10d, r10d
    mov eax, 202
    syscall
    test rax, rax
    js 27f
    dec r13d
    jnz 3b
    call user_test_futex_join
    test eax, eax
    jnz 9f
    cmp qword ptr [rbx + 0x18], 1
    jne 28f
    CLONE_EXIT 0
9:
    mov edi, eax
    mov eax, 231
    syscall

10: CLONE_EXIT 10
11: CLONE_EXIT 11
12: CLONE_EXIT 12
13: CLONE_EXIT 13
14: CLONE_EXIT 14
15: CLONE_EXIT 15
16: CLONE_EXIT 16
17: CLONE_EXIT 17
18: CLONE_EXIT 18
19: CLONE_EXIT 19
20: CLONE_EXIT 20
23: CLONE_EXIT 23
24: CLONE_EXIT 24
26: CLONE_EXIT 26
27: CLONE_EXIT 27
28: CLONE_EXIT 28

/* Waits until the tid word at +0x08 reads 0, 1 s at most per WAIT. Returns
 * 0, 30 when a WAIT timed out, 31 for another result, 32 when it never
 * cleared. Uses r12. */
user_test_futex_join:
    mov r12d, 1000
1:
    mov edx, [rbx + 0x08]
    test edx, edx
    jz 2f
    dec r12d
    jz 3f
    lea rdi, [rbx + 0x08]
    xor esi, esi
    lea r10, [rbx + 0x20]
    mov eax, 202
    syscall
    cmp rax, -110
    je 4f
    test rax, rax
    jz 1b
    cmp rax, -11
    je 1b
    mov eax, 31
    ret
2:
    xor eax, eax
    ret
3:
    mov eax, 32
    ret
4:
    mov eax, 30
    ret

/* The first child: WAIT on +0x00 must return 0 (result 1; 2 otherwise),
 * then 100 ms before exit, so the parent is asleep on the tid word. */
user_test_futex_waiter:
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    xor r10d, r10d
    mov eax, 202
    syscall
    mov ecx, 2
    test rax, rax
    jnz 1f
    mov ecx, 1
1:
    mov [rbx + 0x18], rcx
    mov r12d, 10
2:
    CLONE_NAP
    dec r12d
    jnz 2b
    xor edi, edi
    mov eax, 60
    syscall
    ud2

/* The second child: FUTEX_ROUNDS turns, waiting while the word is 0, then
 * storing 0 and waking the parent. Result 1, or 2 after a timeout. */
user_test_futex_turner:
    mov r13d, FUTEX_ROUNDS
1:
    mov edx, [rbx + 0x10]
    cmp edx, 1
    je 2f
    lea rdi, [rbx + 0x10]
    mov esi, 128
    lea r10, [rbx + 0x30]
    mov eax, 202
    syscall
    cmp rax, -110
    je 3f
    jmp 1b
2:
    mov dword ptr [rbx + 0x10], 0
    lea rdi, [rbx + 0x10]
    mov esi, 129
    mov edx, 1
    xor r10d, r10d
    mov eax, 202
    syscall
    dec r13d
    jnz 1b
    mov qword ptr [rbx + 0x18], 1
    xor edi, edi
    mov eax, 60
    syscall
    ud2
3:
    mov qword ptr [rbx + 0x18], 2
    xor edi, edi
    mov eax, 60
    syscall
    ud2
user_test_futex_end:

/* Index 19: WAIT for 0 on a 0 word with a 20 ms timeout: -ETIMEDOUT, exit
 * 0; any other result, exit 1. The kernel test times it. */
user_test_futex_timeout_start:
    sub rsp, 32
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 20000000
    mov rdi, rsp
    xor esi, esi
    xor edx, edx
    lea r10, [rsp + 8]
    mov eax, 202
    syscall
    cmp rax, -110
    jne 1f
    CLONE_EXIT 0
1:
    CLONE_EXIT 1
user_test_futex_timeout_end:

/* Index 20: a child and the parent both WAIT forever on a 0 word. Only a
 * kill ends the process (137); status 1 means clone failed. */
user_test_futex_kill_start:
    mov rbx, FUTEX_BASE
    mov qword ptr [rbx], 0
    mov eax, 56
    mov edi, CLONE_THREAD_SET
    lea rsi, [rbx + 0x800]
    xor edx, edx
    xor r10d, r10d
    xor r8d, r8d
    syscall
    test rax, rax
    js 2f
1:
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    xor r10d, r10d
    mov eax, 202
    syscall
    jmp 1b
2:
    CLONE_EXIT 1
user_test_futex_kill_end:

ignis_user_test_table:
    .quad user_test_exit_start, user_test_exit_end
    .quad user_test_registers_start, user_test_registers_end
    .quad user_test_spin_start, user_test_spin_end
    .quad user_test_syscalls_start, user_test_syscalls_end
    .quad user_test_null_write_start, user_test_null_write_end
    .quad user_test_hlt_start, user_test_hlt_end
    .quad user_test_cli_start, user_test_cli_end
    .quad user_test_undefined_start, user_test_undefined_end
    .quad user_test_kernel_read_start, user_test_kernel_read_end
    .quad user_test_port_start, user_test_port_end
    .quad user_test_code_write_start, user_test_code_write_end
    .quad user_test_stack_jump_start, user_test_stack_jump_end
    .quad user_test_divide_start, user_test_divide_end
    .quad user_test_fpu_start, user_test_fpu_end
    .quad user_test_nap_start, user_test_nap_end
    .quad user_test_alignment_spin_start, user_test_alignment_spin_end
    .quad user_test_clone_start, user_test_clone_end
    .quad user_test_clone_group_start, user_test_clone_group_end
    .quad user_test_futex_start, user_test_futex_end
    .quad user_test_futex_timeout_start, user_test_futex_timeout_end
    .quad user_test_futex_kill_start, user_test_futex_kill_end

.section .note.GNU-stack,"",@progbits
