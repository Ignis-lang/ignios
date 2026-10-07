/* Throwaway ring 3 programs for the boot self-tests. Each one is
 * position-independent machine code that the kernel copies to the first user
 * page and starts at its first byte, with a fresh stack and no arguments.
 * They talk to the kernel the way a real program does, through SYSCALL with
 * Linux numbers: exit is 60, write is 1.
 *
 * Programs are listed in ignis_user_test_table as start and end address
 * pairs. */

.intel_syntax noprefix

.section .text

/* u64 ignis_user_test_start(u64 index) */
.global ignis_user_test_start
ignis_user_test_start:
    lea rax, [rip + ignis_user_test_table]
    shl rdi, 4
    mov rax, [rax + rdi]
    ret

/* u64 ignis_user_test_size(u64 index) */
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
    mov eax, 9999
    syscall

    cmp rax, -38
    jne user_test_registers_fail

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

    xor edi, edi
    mov eax, 60
    syscall
    ud2
user_test_registers_fail:
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
 * write. */
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
     * whole and prints nothing. */
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

    mov eax, 39
    syscall
    test rax, rax
    jg 1f
    mov edi, 16
    mov eax, 60
    syscall
1:
    mov eax, 24
    syscall
    EXPECT 0, 17

    /* nanosleep: 20 ms, an invalid time, a bad pointer. */
    sub rsp, 16
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], 20000000
    mov eax, 35
    mov rdi, rsp
    xor esi, esi
    syscall
    EXPECT 0, 18

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

    xor edi, edi
    mov eax, 60
    syscall
    ud2
user_test_syscalls_message:
    .ascii "hello from a ring 3 test program\n"
user_test_syscalls_message_end:
user_test_syscalls_end:

.balign 8
ignis_user_test_table:
    .quad user_test_exit_start, user_test_exit_end
    .quad user_test_registers_start, user_test_registers_end
    .quad user_test_spin_start, user_test_spin_end
    .quad user_test_syscalls_start, user_test_syscalls_end

.section .note.GNU-stack,"",@progbits
