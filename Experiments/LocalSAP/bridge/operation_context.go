package main

import (
	"context"
	"sync"
	"time"
)

type sapOperation struct{ cancel context.CancelFunc }

var operations = struct {
	sync.Mutex
	active  map[string]*sapOperation
	pending map[string]time.Time
}{active: make(map[string]*sapOperation), pending: make(map[string]time.Time)}

// Cancellation has a separate lock: it must not wait behind the signing lock.
// A bounded tombstone also covers cancellation racing the initial C call.
func beginSAPOperation(parent context.Context, id string) (context.Context, func()) {
	ctx, cancel := context.WithCancel(parent)
	operation := &sapOperation{cancel: cancel}
	if id == "" {
		return ctx, cancel
	}
	operations.Lock()
	operations.active[id] = operation
	if _, cancelled := operations.pending[id]; cancelled {
		delete(operations.pending, id)
		cancel()
	}
	operations.Unlock()
	return ctx, func() {
		operations.Lock()
		if operations.active[id] == operation {
			delete(operations.active, id)
		}
		operations.Unlock()
		cancel()
	}
}

func cancelSAPOperation(id string) {
	if id == "" {
		return
	}
	operations.Lock()
	defer operations.Unlock()
	if operation := operations.active[id]; operation != nil {
		operation.cancel()
		return
	}
	now := time.Now()
	for key, created := range operations.pending {
		if now.Sub(created) > 2*time.Minute {
			delete(operations.pending, key)
		}
	}
	if len(operations.pending) >= 256 {
		var oldest string
		var when time.Time
		for key, created := range operations.pending {
			if oldest == "" || created.Before(when) {
				oldest, when = key, created
			}
		}
		delete(operations.pending, oldest)
	}
	operations.pending[id] = now
}
