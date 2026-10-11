/* The entry point of a native IgniOS user program, `_start`, and the ELF
 * note that tells the kernel the program speaks the native ABI.
 *
 * The note (Proc::Elf::findAbi in the kernel). user/user.ld puts the section
 * at the start of the rodata segment and also in a PT_NOTE segment:
 *
 *   namesz   7            "IgniOS" and its NUL
 *   descsz   4
 *   type     1            NOTE_ABI
 *   name     "IgniOS\0"   padded to 8 bytes
 *   desc     1            the native ABI version
 *
 * The section is not called .note.* because user/user.ld discards those.
 *
 * `_start` works like the Linux flavour's (user/lib/linux/start.S): RSP points
 * at argc, 16-byte aligned, with no return address. It calls
 *
 *   u64 ignis_main(u64 argc, u64 *argv)
 *
 * and passes the result to the native EXIT call: number 0 in RAX, the status
 * in RDI. */

.intel_syntax noprefix

.section .ignios.note, "a", @note
.balign 4
    .long 7                 /* namesz */
    .long 4                 /* descsz */
    .long 1                 /* type: NOTE_ABI */
    .asciz "IgniOS"
    .balign 4
    .long 1                 /* native ABI version */

.section .text

.global _start
_start:
    xor ebp, ebp
    mov rdi, [rsp]          /* argc */
    lea rsi, [rsp + 8]      /* argv */
    and rsp, -16
    call ignis_main
    mov rdi, rax            /* EXIT(status) */
    xor eax, eax
    syscall
    ud2                     /* EXIT does not return */

.section .note.GNU-stack,"",@progbits
