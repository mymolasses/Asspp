package unicorn

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestInterpreterBudgetKeepsCancellationAndCapsExecution(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	ctx = WithExecutionBudget(ctx, 10*time.Minute)
	engine, err := New(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Close()
	if engine.budget != 5*time.Minute {
		t.Fatal("budget is not bounded", engine.budget)
	}
	cancel()
	if err := engine.StartBounded(0x1000, 0x2000, time.Minute, 0); !errors.Is(err, context.Canceled) {
		t.Fatal("canceled operation entered the guest", err)
	}
}

func TestCancellationInterruptsAlreadyRunningInterpreter(t *testing.T) {
	ctx, cancel := context.WithCancel(WithExecutionBudget(context.Background(), 5*time.Minute))
	defer cancel()
	engine, err := New(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer engine.Close()
	if err := engine.MemMap(0x1000, 0x1000); err != nil {
		t.Fatal(err)
	}
	// jmp to itself: it cannot finish unless cancellation stops execution.
	if err := engine.MemWrite(0x1000, []byte{0xeb, 0xfe}); err != nil {
		t.Fatal(err)
	}
	timer := time.AfterFunc(50*time.Millisecond, cancel)
	defer timer.Stop()
	started := time.Now()
	if err := engine.StartBounded(0x1000, 0x2000, time.Minute, 0); !errors.Is(err, context.Canceled) {
		t.Fatal("running interpreter did not report cancellation", err)
	}
	if time.Since(started) > 2*time.Second {
		t.Fatal("cancellation waited for the execution deadline")
	}
}
