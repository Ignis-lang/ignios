/* IgniOS kernel layout: higher half, one PT_LOAD per permission set. */

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

    /* The boundaries are page aligned and let the kernel map each segment
     * with its own permissions. */
    __text_start = .;

    .text : {
        *(.text .text.*)
    } :text

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    __text_end = .;
    __rodata_start = .;

    .rodata : {
        *(.rodata .rodata.*)
    } :rodata

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    __rodata_end = .;
    __data_start = .;

    .data : {
        *(.data .data.*)
    } :data

    /* Last in the data segment, so its zeros take no space in the file. */
    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    } :data

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    __data_end = .;

    /DISCARD/ : {
        *(.eh_frame*)
        *(.note .note.*)
        *(.comment)
    }
}
