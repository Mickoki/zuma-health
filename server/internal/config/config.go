package config

import (
	"fmt"
	"github.com/Mickoki/zuma-health/server/internal/model"
	"net"
	"os"
	"strconv"
	"time"
)

type Config struct {
	Addr, DB, OllamaURL, Model string
	ModelTimeout               time.Duration
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
func Load() (Config, error) {
	c := Config{Addr: env("ZUMA_ADDR", "127.0.0.1:8080"), DB: env("ZUMA_DB", "./data/zuma.db"), OllamaURL: env("ZUMA_OLLAMA_URL", "http://127.0.0.1:11434"), Model: env("ZUMA_MODEL", "qwen3:8b")}
	host, port, err := net.SplitHostPort(c.Addr)
	if err != nil {
		return c, fmt.Errorf("ZUMA_ADDR: %w", err)
	}
	if host == "localhost" {
		host = "127.0.0.1"
	}
	ip := net.ParseIP(host)
	n, e := strconv.Atoi(port)
	if ip == nil || !ip.IsLoopback() || e != nil || n < 1 || n > 65535 {
		return c, fmt.Errorf("ZUMA_ADDR must be a loopback address with port 1–65535")
	}
	c.Addr = net.JoinHostPort(host, port)
	c.ModelTimeout, err = time.ParseDuration(env("ZUMA_MODEL_TIMEOUT", "120s"))
	if err != nil || c.ModelTimeout <= 0 || c.ModelTimeout > 10*time.Minute {
		return c, fmt.Errorf("ZUMA_MODEL_TIMEOUT must be positive and at most 10m")
	}
	if _, err = model.NewClient(c.OllamaURL, c.Model, c.ModelTimeout); err != nil {
		return c, err
	}
	return c, nil
}
