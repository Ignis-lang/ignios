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
 *   12   divide by zero        killed, SIGFPE (136) */

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

.section .note.GNU-stack,"",@progbits
