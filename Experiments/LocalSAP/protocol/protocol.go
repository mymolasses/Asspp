package sap

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"howett.net/plist"

	apphttp "github.com/majd/ipatool/v2/pkg/http"
)

const (
	setupCertificateKey  = "sign-sap-setup-cert"
	setupBufferKey       = "sign-sap-setup-buffer"
	maxSetupBody         = int64(1 << 20)
	setupRequestTimeout  = 60 * time.Second
	setupRequestAttempts = 3
)

type setupProtocol struct {
	client *http.Client
}

func (p setupProtocol) certificate(ctx context.Context, endpoint string) ([]byte, error) {
	body, err := p.request(ctx, http.MethodGet, endpoint, nil, nil)
	if err != nil {
		return nil, fmt.Errorf("fetch SAP certificate: %w", err)
	}
	return plistBytes(body, setupCertificateKey)
}

func (p setupProtocol) exchange(ctx context.Context, endpoint string, input []byte) ([]byte, error) {
	envelope, err := plist.Marshal(map[string]any{setupBufferKey: input}, plist.XMLFormat)
	if err != nil {
		return nil, fmt.Errorf("encode SAP setup message: %w", err)
	}
	body, err := p.request(ctx, http.MethodPost, endpoint, envelope, map[string]string{
		"Content-Type": "application/x-plist",
	})
	if err != nil {
		return nil, fmt.Errorf("exchange SAP setup message: %w", err)
	}
	return plistBytes(body, setupBufferKey)
}

// request gives certificate/setup each an independent timeout. The parent
// covers the whole SAP job; a slow asset download must not consume the later
// network request's entire budget. Retrying here is safe because each retry
// rebuilds its HTTP request and contains no Apple ID credentials.
func (p setupProtocol) request(parent context.Context, method, endpoint string, payload []byte, headers map[string]string) ([]byte, error) {
	var lastErr error
	for attempt := 1; attempt <= setupRequestAttempts; attempt++ {
		ctx, cancel := context.WithTimeout(parent, setupRequestTimeout)
		request, err := http.NewRequestWithContext(ctx, method, endpoint, bytes.NewReader(payload))
		if err == nil {
			request.Header.Set("User-Agent", apphttp.DefaultUserAgent)
			for key, value := range headers {
				request.Header.Set(key, value)
			}
			body, sendErr := p.send(request)
			cancel()
			if sendErr == nil {
				return body, nil
			}
			lastErr = sendErr
		} else {
			cancel()
			lastErr = err
		}
		if parent.Err() != nil || attempt == setupRequestAttempts {
			break
		}
		time.Sleep(time.Duration(attempt) * time.Second)
	}
	return nil, lastErr
}

func (p setupProtocol) send(request *http.Request) ([]byte, error) {
	response, err := p.client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("send SAP request: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, maxSetupBody))
		return nil, fmt.Errorf("apple returned %s", response.Status)
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, maxSetupBody+1))
	if err != nil {
		return nil, fmt.Errorf("read SAP response: %w", err)
	}
	if int64(len(body)) > maxSetupBody {
		return nil, fmt.Errorf("apple response exceeds %d bytes", maxSetupBody)
	}
	return body, nil
}

func plistBytes(document []byte, key string) ([]byte, error) {
	var values map[string]any
	if _, err := plist.Unmarshal(document, &values); err != nil {
		return nil, fmt.Errorf("decode Apple plist: %w", err)
	}
	value, ok := values[key].([]byte)
	if !ok || len(value) == 0 {
		return nil, errors.New("Apple plist is missing " + key)
	}
	return value, nil
}
