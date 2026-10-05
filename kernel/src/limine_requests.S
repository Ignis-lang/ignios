/*
 * Limine boot protocol requests (base revision 6), read by the bootloader
 * from the loaded image and answered in place before kmain runs.
 *
 * They live here instead of in Ignis because the compiler cannot express them
 * yet: a `static mut` of an array is never emitted, a `static mut` of a
 * @cLayout record cannot take a record literal, and a @cLayout array field is
 * emitted as a pointer. Repros: ignis-os-repros/{static_mut_array,
 * static_mut_record_init,clayout_array_field} in the session scratchpad.
 * kernel/src/limine.ign holds the layouts and reads the responses.
 */

#define LIMINE_COMMON_MAGIC 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b

    .section .limine_requests, "aw", @progbits
    .balign 8

    .globl limine_requests_start_marker
    .type limine_requests_start_marker, @object
limine_requests_start_marker:
    .quad 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf, 0x785c6ed015d3e316, 0x181e920a7852b9d9
    .size limine_requests_start_marker, . - limine_requests_start_marker

    .globl limine_base_revision
    .type limine_base_revision, @object
limine_base_revision:
    .quad 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 6
    .size limine_base_revision, . - limine_base_revision

    .globl limine_framebuffer_request
    .type limine_framebuffer_request, @object
limine_framebuffer_request:
    .quad LIMINE_COMMON_MAGIC, 0x9d5827dcd881dd75, 0xa3148604f6fab11b
    .quad 0
    .quad 0
    .size limine_framebuffer_request, . - limine_framebuffer_request

    .globl limine_memmap_request
    .type limine_memmap_request, @object
limine_memmap_request:
    .quad LIMINE_COMMON_MAGIC, 0x67cf3d9d378a806f, 0xe304acdfc50c3c62
    .quad 0
    .quad 0
    .size limine_memmap_request, . - limine_memmap_request

    .globl limine_hhdm_request
    .type limine_hhdm_request, @object
limine_hhdm_request:
    .quad LIMINE_COMMON_MAGIC, 0x48dcf1cb8ad2b852, 0x63984e959a98244b
    .quad 0
    .quad 0
    .size limine_hhdm_request, . - limine_hhdm_request

    .globl limine_requests_end_marker
    .type limine_requests_end_marker, @object
limine_requests_end_marker:
    .quad 0xadc0e0531bb10d03, 0x9572709f31764c62
    .size limine_requests_end_marker, . - limine_requests_end_marker

    .section .note.GNU-stack, "", @progbits
