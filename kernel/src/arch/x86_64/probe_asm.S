/* Memory probes: a load or a call that may fault in ring 0 without being
 * fatal. Each probe has a known faulting instruction or return address, and
 * Arch::Probe::recover, called by the exception dispatcher before it gives
 * up, moves the saved RIP past the fault when it recognizes one of them.
 * This is the exception-table idea of other kernels (Linux "extable"),
 * reduced to two fixed sites.
 *
 *   ignis_probe_read      the load at ignis_probe_read_load may fault;
 *                         recovery resumes at ignis_probe_read_fault, which
 *                         returns 0
 *   ignis_probe_execute   the call may fault on the fetch at the target;
 *                         recovery pops the return address the call pushed
 *                         and resumes there with rax = 0
 *
 * See concept doc 18. */

.intel_syntax noprefix

.section .text

/* u64 ignis_probe_read(u64 address, u64 *value)
 *
 * rdi = address to load 8 bytes from, rsi = where to store them. Returns 1
 * with *value written, or 0 when the load faulted and *value is untouched. */
.global ignis_probe_read
ignis_probe_read:
    mov eax, 1
ignis_probe_read_load:
    mov rdx, [rdi]
    mov [rsi], rdx
    ret
ignis_probe_read_fault:
    xor eax, eax
    ret

/* u64 ignis_probe_execute(u64 address)
 *
 * Calls the code at rdi. Returns 1 when it ran and returned with rax still
 * 1 (the probe targets hold a lone "ret"), or 0 when the instruction fetch
 * faulted. */
.global ignis_probe_execute
ignis_probe_execute:
    mov eax, 1
    call rdi
ignis_probe_execute_return:
    ret

/* u64 ignis_probe_read_load_address(void) */
.global ignis_probe_read_load_address
ignis_probe_read_load_address:
    lea rax, [rip + ignis_probe_read_load]
    ret

/* u64 ignis_probe_read_fault_address(void) */
.global ignis_probe_read_fault_address
ignis_probe_read_fault_address:
    lea rax, [rip + ignis_probe_read_fault]
    ret

/* u64 ignis_probe_execute_return_address(void) */
.global ignis_probe_execute_return_address
ignis_probe_execute_return_address:
    lea rax, [rip + ignis_probe_execute_return]
    ret

.section .note.GNU-stack,"",@progbits
