package config

import (
	"testing"
	"time"
)

func clear(t *testing.T) {
	for _, key := range []string{"ZUMA_ADDR", "ZUMA_DB", "ZUMA_OLLAMA_URL", "ZUMA_MODEL", "ZUMA_MODEL_TIMEOUT"} {
		t.Setenv(key, "")
	}
}
func TestDefaults(t *testing.T) {
	clear(t)
	c, e := Load()
	if e != nil || c.Addr != "127.0.0.1:8080" || c.DB != "./data/zuma.db" || c.OllamaURL != "http://127.0.0.1:11434" || c.Model != "qwen3:8b" || c.ModelTimeout != 120*time.Second {
		t.Fatal(c, e)
	}
}
func TestRejectNonLoopbackListen(t *testing.T) {
	for _, addr := range []string{"0.0.0.0:8080", ":8080", "192.168.1.2:8080", "example.com:8080", "[::]:8080"} {
		t.Run(addr, func(t *testing.T) {
			clear(t)
			t.Setenv("ZUMA_ADDR", addr)
			if _, e := Load(); e == nil {
				t.Fatal("nonlocal listen accepted")
			}
		})
	}
}
func TestInvalidConfig(t *testing.T) {
	for key, value := range map[string]string{"ZUMA_ADDR": "localhost:no", "ZUMA_MODEL_TIMEOUT": "-1s", "ZUMA_OLLAMA_URL": "https://example.com", "ZUMA_MODEL": "bad:cloud"} {
		t.Run(key, func(t *testing.T) {
			clear(t)
			t.Setenv(key, value)
			if _, e := Load(); e == nil {
				t.Fatal("invalid setting accepted")
			}
		})
	}
}
