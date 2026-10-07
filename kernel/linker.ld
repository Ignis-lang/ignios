/* IgniOS kernel layout: higher half, one PT_LOAD per permission set.
 *
 * Limine loads the ELF produced from this script, so the layout below is the
 * contract between the linker, the bootloader and the kernel itself.
 *
 *   virtual address                      segment   flags   contents
 *   ----------------------------------   -------   -----   --------------------
 *   0xffffffff80000000 __text_start      text      R X     code (.text)
 *                      __text_end
 *   (page aligned)     __rodata_start    rodata    R       constants (.rodata)
 *                      __rodata_end
 *   (page aligned)     __data_start      data      R W     .data, then .bss
 *                      __data_end
 *
 * Why three segments: the kernel page tables (Vmm::mapKernelImage) map each
 * one with its own permissions, so code is never writable and data is never
 * executable. A boundary therefore has to fall on a page boundary: with
 * `-z max-page-size=0x1000` (see the Makefile) CONSTANT(MAXPAGESIZE) is
 * 4096.
 *
 * Why 0xffffffff80000000: the top 2 GiB of the address space is the range
 * that the `-mcmodel=kernel` code model assumes (every symbol address fits a
 * sign-extended 32-bit value), and the Limine protocol loads the kernel
 * there. In the page tables this is PML4 entry 511, PDPT entry 510.
 *
 * The __*_start and __*_end symbols have an address and no value. The kernel
 * reads them through `extern LinkerSymbols` in mm/vmm.ign.
 *
 * See concept doc 01. */

OUTPUT_FORMAT(elf64-x86-64)

/* The ELF entry point. Limine jumps here: the Ignis function `kmain`
 * (kernel/src/main.ign) carries the matching @externName. */
ENTRY(kmain)

/* Program headers. FLAGS uses the ELF p_flags bits: 1 execute, 2 write, 4 read. */
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

    /* Includes the Limine request records, which Limine finds by scanning the
     * loaded image (see kernel/src/boot/limine.ign). */
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

    /* Not needed by a kernel without unwinding or a C runtime. */
    /DISCARD/ : {
        *(.eh_frame*)
        *(.note .note.*)
        *(.comment)
    }
}
