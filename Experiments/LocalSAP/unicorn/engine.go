// Static cgo adapter for ipatool's SAP machine. No dlopen or executable callbacks.
package unicorn

/*
#include <unicorn/unicorn.h>
extern void sapCodeHook(uintptr_t, uint64_t, uint32_t);
static void hookBridge(uc_engine *uc, uint64_t address, uint32_t size, void *data) {
    sapCodeHook((uintptr_t)data, address, size);
}
static uc_err addHook(uc_engine *uc, uc_hook *hook, uintptr_t id, uint64_t begin, uint64_t end) {
    return uc_hook_add(uc, hook, UC_HOOK_CODE, (void *)hookBridge, (void *)id, begin, end);
}
static uc_err limitCache(uc_engine *uc) {
    return uc_ctl_set_tcg_buffer_size(uc, (uint32_t)(64 * 1024 * 1024));
}
*/
import "C"

import (
	"context"
	"errors"
	"fmt"
	"runtime/cgo"
	"time"
	"unsafe"
)

const (
	RegRAX = int(C.UC_X86_REG_RAX)
	RegRCX = int(C.UC_X86_REG_RCX)
	RegRDX = int(C.UC_X86_REG_RDX)
	RegRDI = int(C.UC_X86_REG_RDI)
	RegRSI = int(C.UC_X86_REG_RSI)
	RegRSP = int(C.UC_X86_REG_RSP)
	RegRIP = int(C.UC_X86_REG_RIP)
	RegR8  = int(C.UC_X86_REG_R8)
	RegR9  = int(C.UC_X86_REG_R9)
)

type Engine struct {
	handle *C.uc_engine
	hooks  map[*Hook]bool
}
type CodeHook func(uint64, uint32)
type Hook struct {
	engine   *Engine
	handle   C.uc_hook
	callback cgo.Handle
}

func result(code C.uc_err) error {
	if code == C.UC_ERR_OK {
		return nil
	}
	return fmt.Errorf("unicorn: %s", C.GoString(C.uc_strerror(code)))
}
func New(ctx context.Context) (*Engine, error) {
	if ctx == nil {
		return nil, errors.New("nil context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	e := &Engine{hooks: make(map[*Hook]bool)}
	if err := result(C.uc_open(C.UC_ARCH_X86, C.UC_MODE_64, &e.handle)); err != nil {
		return nil, err
	}
	if err := result(C.limitCache(e.handle)); err != nil {
		C.uc_close(e.handle)
		return nil, err
	}
	return e, nil
}
func (e *Engine) MemMap(address, size uint64) error {
	return result(C.uc_mem_map(e.handle, C.uint64_t(address), C.size_t(size), C.UC_PROT_ALL))
}
func (e *Engine) MemUnmap(address, size uint64) error {
	return result(C.uc_mem_unmap(e.handle, C.uint64_t(address), C.size_t(size)))
}
func (e *Engine) MemReadInto(data []byte, address uint64) error {
	if len(data) == 0 {
		return nil
	}
	return result(C.uc_mem_read(e.handle, C.uint64_t(address), unsafe.Pointer(&data[0]), C.size_t(len(data))))
}
func (e *Engine) MemRead(address, size uint64) ([]byte, error) {
	if size > 256<<20 {
		return nil, errors.New("guest read exceeds limit")
	}
	data := make([]byte, int(size))
	return data, e.MemReadInto(data, address)
}
func (e *Engine) MemWrite(address uint64, data []byte) error {
	if len(data) == 0 {
		return nil
	}
	return result(C.uc_mem_write(e.handle, C.uint64_t(address), unsafe.Pointer(&data[0]), C.size_t(len(data))))
}
func (e *Engine) RegRead(register int) (uint64, error) {
	var v uint64
	err := result(C.uc_reg_read(e.handle, C.int(register), unsafe.Pointer(&v)))
	return v, err
}
func (e *Engine) RegWrite(register int, value uint64) error {
	return result(C.uc_reg_write(e.handle, C.int(register), unsafe.Pointer(&value)))
}
func (e *Engine) Start(begin, end uint64) error { return e.StartBounded(begin, end, 5*time.Minute, 0) }
func (e *Engine) StartBounded(begin, end uint64, timeout time.Duration, limit uint64) error {
	if timeout <= 0 {
		return errors.New("invalid timeout")
	}
	if err := result(C.uc_emu_start(e.handle, C.uint64_t(begin), C.uint64_t(end), C.uint64_t(timeout/time.Microsecond), C.size_t(limit))); err != nil {
		return err
	}
	var timedOut C.size_t
	if err := result(C.uc_query(e.handle, C.UC_QUERY_TIMEOUT, &timedOut)); err != nil {
		return err
	}
	if timedOut != 0 {
		return errors.New("SAP interpreter timed out")
	}
	return nil
}
func (e *Engine) Stop() error { return result(C.uc_emu_stop(e.handle)) }
func (e *Engine) AddCodeHook(begin, end uint64, callback CodeHook) (*Hook, error) {
	if callback == nil {
		return nil, errors.New("nil callback")
	}
	h := &Hook{engine: e, callback: cgo.NewHandle(callback)}
	if err := result(C.addHook(e.handle, &h.handle, C.uintptr_t(h.callback), C.uint64_t(begin), C.uint64_t(end))); err != nil {
		h.callback.Delete()
		return nil, err
	}
	e.hooks[h] = true
	return h, nil
}

//export sapCodeHook
func sapCodeHook(id C.uintptr_t, address C.uint64_t, size C.uint32_t) {
	cgo.Handle(id).Value().(CodeHook)(uint64(address), uint32(size))
}
func (h *Hook) Close() error {
	if h.engine == nil {
		return nil
	}
	if err := result(C.uc_hook_del(h.engine.handle, h.handle)); err != nil {
		return err
	}
	delete(h.engine.hooks, h)
	h.callback.Delete()
	h.engine = nil
	return nil
}

// The SAP Signer serializes operations. Close is called after guest execution returns.
func (e *Engine) Close() error {
	if e == nil || e.handle == nil {
		return nil
	}
	var err error
	for h := range e.hooks {
		err = errors.Join(err, h.Close())
	}
	err = errors.Join(err, result(C.uc_close(e.handle)))
	e.handle = nil
	return err
}
