package main

import (
	"fmt"
	"net/http"

	"github.com/aleogr/lab/k8s/pod/app/internal/privlib1"
	"github.com/caarlos0/env/v10"
)

type config struct {
	Port int `env:"PORT" envDefault:"8080"`
}

func web(cfg config) {
	http.HandleFunc(
		"/",
		func(w http.ResponseWriter, req *http.Request) {
			fmt.Fprintf(
				w,
				"utils.IntMin(1,-2) = %d",
				privlib1.IntMin(1, -2),
			)
		},
	)
	http.ListenAndServe(":"+fmt.Sprint(cfg.Port), nil)
}

func main() {
	cfg := config{}
	if err := env.Parse(&cfg); err != nil {
		fmt.Printf("%v\n", err)
	}
	fmt.Println(cfg)
	web(cfg)
}
