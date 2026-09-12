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
	"sync"
	"time"
	"unsafe"
)

var signing sync.Mutex

type request struct {
	Setup       string `json:"setup"`
	Certificate string `json:"certificate"`
	Device      string `json:"device"`
	Version     uint32 `json:"version"`
	Body        []byte `json:"body"`
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
	if err == nil {
		var hardware []byte
		hardware, err = hex.DecodeString(req.Device)
		if err == nil {
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
			defer cancel()
			var signer sap.ActionSigner
			signer, err = sap.NewSigner(ctx, sap.Config{SetupURL: req.Setup, CertificateURL: req.Certificate, Version: req.Version, HardwareID: hardware})
			if err == nil {
				answer.Signature, err = signer.Sign(req.Body)
				closeErr := signer.Close()
				if err == nil {
					err = closeErr
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
