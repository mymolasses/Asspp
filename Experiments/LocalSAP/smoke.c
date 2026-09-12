#include <stdint.h>
#include <stdio.h>
#include <unicorn/unicorn.h>

// Exercise the same x86-64 guest architecture used by ipatool SAP.
// This checks interpreter execution, not Apple login or iPhone runtime behavior.
int main(void) {
    uc_engine *engine = NULL;
    const uint64_t base = 0x100000;
    const unsigned char code[] = {0x48, 0xc7, 0xc0, 0x2a, 0, 0, 0};
    uint64_t result = 0;
    uc_err error = uc_open(UC_ARCH_X86, UC_MODE_64, &engine);
    if (error != UC_ERR_OK) goto done;
    error = uc_mem_map(engine, base, 4096, UC_PROT_ALL);
    if (error != UC_ERR_OK) goto done;
    error = uc_mem_write(engine, base, code, sizeof(code));
    if (error != UC_ERR_OK) goto done;
    error = uc_emu_start(engine, base, base + sizeof(code), 1000000, 1);
    if (error != UC_ERR_OK) goto done;
    error = uc_reg_read(engine, UC_X86_REG_RAX, &result);
done:
    if (engine) uc_close(engine);
    if (error != UC_ERR_OK || result != 42) {
        fprintf(stderr, "TCI smoke failed: %s, RAX=%llu\n", uc_strerror(error), (unsigned long long)result);
        return 1;
    }
    puts("x86-64 interpreter smoke passed");
    return 0;
}
