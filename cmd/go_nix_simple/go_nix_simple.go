package main

import (
	"fmt"
	"net/http"
	"time"

	"github.com/google/martian/log"
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

	go initPromHandler(promPathCst, promListenCst)
	pC.WithLabelValues("main", "start", "count").Inc()

	for {
		fmt.Println("Hello")
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
			log.Errorf("prometheus error")
		}
	}()
}
