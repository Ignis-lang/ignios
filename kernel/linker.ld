/* Ignis OS kernel layout: higher half, one PT_LOAD per permission set. */

OUTPUT_FORMAT(elf64-x86-64)
ENTRY(kmain)

PHDRS
{
    text    PT_LOAD FLAGS(0x5); /* R + X */
    rodata  PT_LOAD FLAGS(0x4); /* R */
    data    PT_LOAD FLAGS(0x6); /* R + W */
}

SECTIONS
{
    /* Limine requires the kernel in the top 2 GiB of the address space. */
    . = 0xffffffff80000000;

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

    /* Last in the data segment, so its zeros take no space in the file. */
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
