package main

import (
	"context"
	"fmt"
	"testing"
)

func TestCancellationReachesActiveOperationWithoutCancellingOtherAccount(t *testing.T) {
	first, finishFirst := beginSAPOperation(context.Background(), "cancel-first")
	defer finishFirst()
	second, finishSecond := beginSAPOperation(context.Background(), "retain-second")
	defer finishSecond()
	cancelSAPOperation("cancel-first")
	if first.Err() != context.Canceled {
		t.Fatal("active operation was not canceled")
	}
	if second.Err() != nil {
		t.Fatal("unrelated operation was canceled")
	}
}

func TestCancellationBeforeCOperationRegistration(t *testing.T) {
	cancelSAPOperation("cancel-before-start")
	ctx, finish := beginSAPOperation(context.Background(), "cancel-before-start")
	defer finish()
	if ctx.Err() != context.Canceled {
		t.Fatal("registration lost an earlier cancellation")
	}
}

func TestOperationCleanupAndBoundedPendingCancellations(t *testing.T) {
	ctx, finish := beginSAPOperation(context.Background(), "completed-operation")
	finish()
	if ctx.Err() != context.Canceled {
		t.Fatal("finished context leaked")
	}
	operations.Lock()
	_, exists := operations.active["completed-operation"]
	operations.Unlock()
	if exists {
		t.Fatal("completed operation leaked")
	}
	for i := 0; i < 1024; i++ {
		cancelSAPOperation(fmt.Sprintf("bounded-%d", i))
	}
	operations.Lock()
	count := len(operations.pending)
	operations.Unlock()
	if count > 256 {
		t.Fatal("unbounded cancellation tombstones", count)
	}
}
