package main

import (
	"context"
	"errors"
	"fmt"
	"github.com/Mickoki/zuma-health/server/internal/config"
	"github.com/Mickoki/zuma-health/server/internal/httpapi"
	"github.com/Mickoki/zuma-health/server/internal/model"
	"github.com/Mickoki/zuma-health/server/internal/store"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	s, err := store.Open(cfg.DB)
	if err != nil {
		return fmt.Errorf("open storage: %w", err)
	}
	defer s.Close()
	m, err := model.NewClient(cfg.OllamaURL, cfg.Model, cfg.ModelTimeout)
	if err != nil {
		return err
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	server := &http.Server{Addr: cfg.Addr, Handler: httpapi.New(s, m), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: cfg.ModelTimeout + 15*time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 32 << 10, BaseContext: func(net.Listener) context.Context { return ctx }}
	done := make(chan error, 1)
	go func() { done <- server.ListenAndServe() }()
	log.Printf("Zuma API listening at http://%s (model %s; local use only)", cfg.Addr, cfg.Model)
	select {
	case err = <-done:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
		shutdownCtx, stop := context.WithTimeout(context.Background(), 10*time.Second)
		defer stop()
		if err = server.Shutdown(shutdownCtx); err != nil {
			server.Close()
			return err
		}
		err = <-done
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	}
}
func main() {
	if err := run(); err != nil {
		log.Print(err)
		os.Exit(1)
	}
}
