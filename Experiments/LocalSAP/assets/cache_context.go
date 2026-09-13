package assets

import (
	"context"
	"fmt"
	"path/filepath"
)

type cacheDirectoryKey struct{}

// WithCacheDirectory scopes the iOS sandbox path to one signer, without
// modifying the host process environment (important for LiveContainer).
func WithCacheDirectory(ctx context.Context, directory string) context.Context {
	return context.WithValue(ctx, cacheDirectoryKey{}, directory)
}

func cacheDirectoryForContext(ctx context.Context) (string, error) {
	if directory, supplied := ctx.Value(cacheDirectoryKey{}).(string); supplied {
		if !filepath.IsAbs(directory) {
			return "", fmt.Errorf("SAP cache directory must be an absolute sandbox path")
		}
		return filepath.Join(directory, "apple-assets-v2"), nil
	}
	// Desktop integration tests retain the upstream default. The iOS bridge
	// always supplies a path, including an empty one which fails explicitly.
	return cacheDirectory()
}
