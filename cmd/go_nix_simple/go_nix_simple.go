package main

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const (
	promListenCst           = ":9108"
	promPathCst             = "/metrics"
	promMaxRequestsInFlight = 10
	promEnableOpenMetrics   = true
)

var (
	// Passed by "go build -ldflags" for the show version
	commit  string
	date    string
	version string

	pC = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Subsystem: "counters",
			Name:      "main",
			Help:      "main counters",
		},
		[]string{"function", "variable", "type"},
	)
)

func main() {

	log.Printf("go_nix_simple commit:%s\tdate(UTC):%s\tversion:%s", commit, date, version)

	go initPromHandler(promPathCst, promListenCst)

	// pC.WithLabelValues("main", "start", "count").Inc()

	for i := 0; ; i++ {
		fmt.Printf("Hello %d", i)
		pC.WithLabelValues("main", "hello", "count").Inc()
		time.Sleep(10 * time.Second)
	}
}

// initPromHandler starts the prom handler with error checking
func initPromHandler(promPath string, promListen string) {

	// https: //pkg.go.dev/github.com/prometheus/client_golang/prometheus/promhttp?tab=doc#HandlerOpts
	http.Handle(promPath, promhttp.HandlerFor(
		prometheus.DefaultGatherer,
		promhttp.HandlerOpts{
			EnableOpenMetrics:   promEnableOpenMetrics,
			MaxRequestsInFlight: promMaxRequestsInFlight,
		},
	))
	go func() {
		err := http.ListenAndServe(promListen, nil)
		if err != nil {
			log.Fatal("prometheus error")
		}
	}()
}
