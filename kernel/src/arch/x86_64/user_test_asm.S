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

.balign 8
ignis_user_test_table:
    .quad user_test_exit_start, user_test_exit_end
    .quad user_test_registers_start, user_test_registers_end
    .quad user_test_spin_start, user_test_spin_end

.section .note.GNU-stack,"",@progbits
