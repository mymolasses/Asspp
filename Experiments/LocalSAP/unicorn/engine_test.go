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
