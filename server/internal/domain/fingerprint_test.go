package domain

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"testing"
)

func TestFingerprintInvalidatesLegacyWordingCache(t *testing.T) {
	r := Calculate(sample(), nil)
	legacy, err := json.Marshal(r)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(legacy)
	if Fingerprint(r) == hex.EncodeToString(sum[:]) {
		t.Fatal("legacy report-only fingerprint must not validate an old-language explanation")
	}
	current, err := json.Marshal(struct {
		Report Report `json:"report"`
		Facts  []Fact `json:"facts"`
	}{r, BuildFacts(r)})
	if err != nil {
		t.Fatal(err)
	}
	sum = sha256.Sum256(current)
	if Fingerprint(r) != hex.EncodeToString(sum[:]) {
		t.Fatal("fingerprint must include current fact wording")
	}
}
