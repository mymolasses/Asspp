package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"github.com/majd/ipatool/v2/internal/sap"
	"github.com/majd/ipatool/v2/internal/sap/assets"
	"sync"
	"time"
	"unsafe"
)

var signing sync.Mutex
var sessions = make(map[string]sap.ActionSigner)

type request struct {
	CacheDirectory string `json:"cacheDirectory"`
	Session        string `json:"session"`
	Close          bool   `json:"close"`
	Setup          string `json:"setup"`
	Certificate    string `json:"certificate"`
	Device         string `json:"device"`
	Version        uint32 `json:"version"`
	Body           []byte `json:"body"`
}
type response struct {
	Signature []byte `json:"signature,omitempty"`
	Error     string `json:"error,omitempty"`
}

//export AssppSAPSign
func AssppSAPSign(input *C.char) *C.char {
	signing.Lock()
	defer signing.Unlock()
	answer := response{}
	var req request
	err := json.Unmarshal([]byte(C.GoString(input)), &req)
	if err == nil && req.Close {
		if signer := sessions[req.Session]; signer != nil {
			err = signer.Close()
			delete(sessions, req.Session)
		}
		if err != nil {
			answer.Error = err.Error()
		}
		data, _ := json.Marshal(answer)
		return C.CString(string(data))
	}
	if err == nil {
		var hardware []byte
		hardware, err = hex.DecodeString(req.Device)
		if err == nil {
			// Asset extraction, emulator startup and the Apple SAP setup are
			// separate slow phases on iOS. A 10 minute shared deadline can expire
			// during initial asset loading and surface later as a certificate/setup
			// timeout. Keep a bounded but realistic end-to-end budget.
			ctx, cancel := context.WithTimeout(context.Background(), 25*time.Minute)
			defer cancel()
			ctx = assets.WithCacheDirectory(ctx, req.CacheDirectory)
			signer := sessions[req.Session]
			if signer == nil {
				signer, err = sap.NewSigner(ctx, sap.Config{SetupURL: req.Setup, CertificateURL: req.Certificate, Version: req.Version, HardwareID: hardware})
				if err == nil && req.Session != "" {
					sessions[req.Session] = signer
				}
			}
			if err == nil {
				answer.Signature, err = signer.Sign(req.Body)
				if req.Session == "" || err != nil {
					closeErr := signer.Close()
					delete(sessions, req.Session)
					if err == nil {
						err = closeErr
					}
				}
			}
		}
	}
	if err != nil {
		answer.Error = err.Error()
	}
	data, _ := json.Marshal(answer)
	return C.CString(string(data))
}

//export AssppSAPFree
func AssppSAPFree(value *C.char) { C.free(unsafe.Pointer(value)) }
func main()                      {}
