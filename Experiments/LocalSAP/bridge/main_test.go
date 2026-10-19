package main

import "testing"

func TestKBSyncInput(t *testing.T) {
	if dsid, err := validateKBSyncInput(make([]byte, 6), "18446744073709551615"); err != nil || dsid != ^uint64(0) {
		t.Fatal(dsid, err)
	}
	for _, value := range []string{"", "0", "-1", "x", "18446744073709551616"} {
		if _, err := validateKBSyncInput(make([]byte, 6), value); err == nil {
			t.Fatal(value)
		}
	}
	if _, err := validateKBSyncInput(make([]byte, 5), "1"); err == nil {
		t.Fatal("bad GUID accepted")
	}
}
