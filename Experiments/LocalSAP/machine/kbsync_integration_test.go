package machine

import (
	"context"
	"github.com/majd/ipatool/v2/internal/sap/assets"
	"github.com/majd/ipatool/v2/internal/sap/unicorn"
	"testing"
	"time"
)

// No Apple ID/password/token is used. Exercise the same interpreter path as
// the device bridge, including StoreAgent loading and guest buffer disposal.
func TestKBSyncIntegration(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	ctx = assets.WithCacheDirectory(ctx, t.TempDir())
	ctx = unicorn.WithExecutionBudget(ctx, 5*time.Minute)
	bundle, err := assets.Load(ctx)
	if err != nil {
		t.Fatal(err)
	}
	blob, err := GenerateKBSync(ctx, bundle, []byte{0, 17, 34, 51, 68, 85}, 123456789)
	if err != nil {
		t.Fatal(err)
	}
	if len(blob) == 0 {
		t.Fatal("kbsync is empty")
	}
	t.Logf("Generated %d bytes with dummy account/device identifiers", len(blob))
}
