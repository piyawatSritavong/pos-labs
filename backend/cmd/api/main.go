package main

import (
	"log"

	"backend/internal/app"
	"backend/internal/config"
)

func main() {
	cfg := config.Load().WithCloudDefaults()
	if err := app.RunServer(cfg); err != nil {
		log.Fatalf("server stopped with error: %v", err)
	}
}
