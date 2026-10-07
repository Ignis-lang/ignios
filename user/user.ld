/* Layout of an IgniOS user program: low user addresses, one PT_LOAD per
 * permission set, each starting on its own page, so the kernel loader can map
 * every segment with its own permissions and never has two segments in one
 * page.
 *
 *   virtual address   segment   flags   contents
 *   ---------------   -------   -----   ----------------------------------
 *   0x400000          text      R X     code (.text), the entry point
 *   next page         rodata    R       constants (.rodata)
 *   next page         data      R W     .data, then .bss (zero-filled)
 *
 * The kernel (kernel/src/elf.ign) loads each PT_LOAD at its p_vaddr and
 * refuses a segment that is both writable and executable, or that shares a
 * page with another one. The page size is 4 KiB because the Makefile links with
 * `-z max-page-size=0x1000`, which sets CONSTANT(MAXPAGESIZE).
 *
 * The kernel gives the process a stack that ends at 0x7FFFFFFFF000; the stack
 * is not part of the image. See concept doc 15. */

OUTPUT_FORMAT(elf64-x86-64)

/* The entry point is the Ignis function annotated @externName("_start"). */
ENTRY(_start)

/* ELF p_flags: 1 execute, 2 write, 4 read. */
PHDRS
{
    text    PT_LOAD FLAGS(0x5); /* R + X */
    rodata  PT_LOAD FLAGS(0x4); /* R */
    data    PT_LOAD FLAGS(0x6); /* R + W */
}

SECTIONS
{
    /* The first user address a program may use. Page 0 stays unmapped so a
     * null pointer faults. */
    . = 0x400000;

    .text : {
        *(.text .text.*)
    } :text

    . = ALIGN(CONSTANT(MAXPAGESIZE));

    .rodata : {
        *(.rodata .rodata.*)
    } :rodata

    . = ALIGN(CONSTANT(MAXPAGESIZE));

    .data : {
        *(.data .data.*)
    } :data

    /* Last in the data segment: its memory size exceeds its file size, and the
     * loader zeroes the difference. */
    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    } :data

    /* Not needed by a program without unwinding. */
    /DISCARD/ : {
        *(.eh_frame*)
        *(.note .note.*)
        *(.comment)
    }
}
