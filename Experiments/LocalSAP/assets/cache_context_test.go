package assets

import (
	"context"
	"path/filepath"
	"testing"
)

func TestExplicitSandboxCacheDirectory(t *testing.T) {
	first, second := t.TempDir(), t.TempDir()
	for _, root := range []string{first, second} {
		directory, err := cacheDirectoryForContext(WithCacheDirectory(context.Background(), root))
		if err != nil || directory != filepath.Join(root, "apple-assets-v2") {
			t.Fatalf("sandbox cache = %q, %v", directory, err)
		}
	}
	for _, root := range []string{"", "relative/cache"} {
		if _, err := cacheDirectoryForContext(WithCacheDirectory(context.Background(), root)); err == nil {
			t.Fatalf("accepted invalid sandbox path %q", root)
		}
	}
}
