package main

import (
	"fmt"
	"net/http"

	"github.com/aleogr/lab/internal/privlib1"
)

func main() {
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
	http.ListenAndServe(":8080", nil)
}
