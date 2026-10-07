/* Layout of an IgniOS user program: low user addresses, one PT_LOAD per
 * permission set, each starting on its own page, so the kernel loader can map
 * every segment with its own permissions and never has two segments in one
 * page. */

OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start)

PHDRS
{
    text    PT_LOAD FLAGS(0x5); /* R + X */
    rodata  PT_LOAD FLAGS(0x4); /* R */
    data    PT_LOAD FLAGS(0x6); /* R + W */
}

SECTIONS
{
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

    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    } :data

    /DISCARD/ : {
        *(.eh_frame*)
        *(.note .note.*)
        *(.comment)
    }
}
