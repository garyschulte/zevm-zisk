/* Linker script for Zisk zkVM
 * ROM: 0x80000000 - 0x90000000 (256MB) - code and read-only data
 * RAM: 0xa0020000 - 0xc0000000 (512MB-128KB) - writable data
 * Note: 0xa0000000-0xa0020000 is reserved by Zisk
 */

OUTPUT_FORMAT("elf64-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x80000000, LENGTH = 0x10000000
    RAM (rw)  : ORIGIN = 0xa0020000, LENGTH = 0x1FFE0000
}

PHDRS
{
    text PT_LOAD FLAGS(7);
    data PT_LOAD FLAGS(6);
    bss PT_LOAD FLAGS(6);
}

SECTIONS
{
    /* Code in ROM */
    .text : {
        *(.text._start)
        *(.text .text.*)
        . = ALIGN(4);
    } >ROM :text

    /* Read-only data in ROM */
    .rodata : {
        *(.rodata .rodata.*)
        . = ALIGN(8);
    } >ROM :text

    /* Writable data in RAM */
    .data : {
        __data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        __data_end = .;
    } >RAM AT>ROM :data

    /* Set global pointer after data */
    . = ALIGN(8);
    PROVIDE(__global_pointer$ = .);

    .bss : {
        __bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        __bss_end = .;
    } >RAM AT>RAM :bss

    /* Heap section for large buffers (not loaded from file) */
    .heap (NOLOAD) : ALIGN(0x1000) {
        __heap_start = .;
        *(.heap)
        . = ALIGN(0x1000);
        __heap_end = .;
    } >RAM

    _end = .;

    /* Discard unnecessary sections */
    /DISCARD/ : {
        *(.comment)
        *(.note.GNU-stack)
        *(.gnu.hash)
        *(.dynsym)
        *(.dynstr)
        *(.eh_frame)
        *(.eh_frame_hdr)
    }
}
