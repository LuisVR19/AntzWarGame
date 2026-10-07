// Package idgen generates random identifiers.
package idgen

import (
	"crypto/rand"
	"encoding/hex"
)

// New returns prefix + "-" + n random bytes hex encoded.
func New(prefix string, n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic("idgen: crypto/rand failed: " + err.Error())
	}
	if prefix == "" {
		return hex.EncodeToString(b)
	}
	return prefix + "-" + hex.EncodeToString(b)
}
