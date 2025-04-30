package main

import (
	"context"
	"database/sql"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	// Ensure the ClickHouse driver is imported for side effects when enabled
	_ "github.com/ClickHouse/clickhouse-go/v2"

	pyroscope "github.com/grafana/pyroscope-go"
	"github.com/nats-io/nats.go"
	"github.com/pkg/profile"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
)

const (
	sleepTimeCst = 6 * time.Second

	debugLevelCst = 11 // Default debug level

	//promListenCst           = ":9108"
	promPathCst             = "/metrics"
	promMaxRequestsInFlight = 10
	promEnableOpenMetrics   = true

	signalChannelSizeCst = 10 // Increased buffer size
	shutdownTimeoutCst   = 5 * time.Second

	// Default connection strings
	defaultClickHouseDSN = "clickhouse://user:password@localhost:9000/default?dial_timeout=10s&compress=true"
	defaultNatsURL       = nats.DefaultURL // "nats://127.0.0.1:4222"
	defaultRedisAddr     = "localhost:6379"
)

var (
	// Passed by "go build -ldflags" for the show version
	commit  string
	date    string
	version string

	debugLevel uint

	chDB   *sql.DB       // ClickHouse DB handle
	natsC  *nats.Conn    // NATS connection
	redisC *redis.Client // Redis client

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

	pyroscopeServer := flag.String("pyroscope.server", "", "Pyroscope server address (e.g., http://localhost:4040)")
	pyroscopeApp := flag.String("pyroscope.app", "go_nix_simple", "Application name for Pyroscope")

	clickhouseEnable := flag.Bool("clickhouse.enable", false, "Enable ClickHouse connection test")
	clickhouseDSN := flag.String("clickhouse.dsn", defaultClickHouseDSN, "ClickHouse DSN (Data Source Name)")

	natsEnable := flag.Bool("nats.enable", false, "Enable NATS connection test")
	natsURL := flag.String("nats.url", defaultNatsURL, "NATS server URL(s), comma-separated")

	redisEnable := flag.Bool("redis.enable", false, "Enable Redis connection test")
	redisAddr := flag.String("redis.addr", defaultRedisAddr, "Redis server address (host:port)")
	redisPassword := flag.String("redis.password", "", "Redis password (optional)")
	redisDB := flag.Int("redis.db", 0, "Redis database number")

	// ./gdp --profile.mode cpu
	// timeout 1h ./gdp --profile.mode cpu
	profileMode := flag.String("profile.mode", "", "enable profiling mode, one of [cpu, mem, memheap, mutex, block, trace, goroutine]")
	promPort := flag.Uint("prom.port", 9108, "Prometheus port")

	promListAddr := fmt.Sprintf(":%d", *promPort)

	d := flag.Uint("d", debugLevelCst, "debug level")
	v := flag.Bool("v", false, "show version")

	flag.Parse()

	debugLevel = *d
	log.SetFlags(log.LstdFlags | log.Lmicroseconds | log.LUTC | log.Lshortfile | log.Lmsgprefix)
	log.SetPrefix("go_nix_simple: ")

	if *v {
		// Use fmt.Printf for version output as it's informational, not an error/log event
		fmt.Printf("go_nix_simple commit:%s\tdate(UTC):%s\tversion:%s\n", commit, date, version)
		os.Exit(0)
	}

	log.Printf("Starting go_nix_simple (PID: %d)", os.Getpid())
	if debugLevel > 10 {
		log.Printf("Debug level set to: %d", debugLevel)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	complete := make(chan struct{})
	var sigHandlerWg sync.WaitGroup
	sigHandlerWg.Add(1)
	go initSignalHandler(cancel, complete, &sigHandlerWg)

	go initPromHandler(ctx, promPathCst, promListAddr)

	// "github.com/pkg/profile"
	// https://dave.cheney.net/2013/07/07/introducing-profile-super-simple-profiling-for-go-programs
	// e.g. ./gdp -profile.mode trace
	// go tool trace trace.out
	// e.g. ./gdp -profile.mode cpu
	// go tool pprof -http=":8081" gdp cpu.pprof
	if *profileMode != "" {
		log.Printf("Local profiling enabled: %s", *profileMode)
		switch *profileMode {
		case "cpu":
			defer profile.Start(profile.CPUProfile, profile.ProfilePath(".")).Stop()
		case "mem":
			defer profile.Start(profile.MemProfile, profile.ProfilePath(".")).Stop()
		case "memheap":
			defer profile.Start(profile.MemProfileHeap, profile.ProfilePath(".")).Stop()
		case "mutex":
			defer profile.Start(profile.MutexProfile, profile.ProfilePath(".")).Stop()
		case "block":
			defer profile.Start(profile.BlockProfile, profile.ProfilePath(".")).Stop()
		case "trace":
			defer profile.Start(profile.TraceProfile, profile.ProfilePath(".")).Stop()
		case "goroutine":
			defer profile.Start(profile.GoroutineProfile, profile.ProfilePath(".")).Stop()
		default:
			log.Printf("Warning: Unknown profile mode '%s'. No local profiling started.", *profileMode)
		}
	}

	if *pyroscopeServer != "" {
		setupPyroscope(*pyroscopeServer, *pyroscopeApp)
	}

	var chErr error
	if *clickhouseEnable {
		chDB, chErr = setupClickHouse(ctx, *clickhouseDSN)
		if chErr != nil {
			log.Printf("ClickHouse setup failed: %v. Will not attempt interaction.", chErr)
			if chDB != nil {
				chDB.Close()
				chDB = nil
			}
		}
	}
	defer func() {
		if chDB != nil {
			log.Println("Closing ClickHouse connection...")
			if err := chDB.Close(); err != nil {
				log.Printf("Error closing ClickHouse connection: %v", err)
			} else {
				log.Println("ClickHouse connection closed.")
			}
		}
	}()

	var natsErr error
	if *natsEnable {
		natsC, natsErr = setupNATS(*natsURL)
		if natsErr != nil {
			log.Printf("NATS setup failed: %v. Will not attempt interaction.", natsErr)
			if natsC != nil {
				natsC.Close()
				natsC = nil
			}
		}
	}
	defer func() {
		if natsC != nil && natsC.IsConnected() {
			log.Println("Draining and closing NATS connection...")
			if err := natsC.Drain(); err != nil {
				log.Printf("Error draining NATS connection: %v", err)
			}
			natsC.Close()
			log.Println("NATS connection closed.")
		} else if natsC != nil {
			natsC.Close()
			log.Println("NATS connection closed (was not connected).")
		}
	}()

	var redisErr error
	if *redisEnable {
		redisC, redisErr = setupRedis(ctx, *redisAddr, *redisPassword, *redisDB)
		if redisErr != nil {
			log.Printf("Redis setup failed: %v. Will not attempt interaction.", redisErr)
			if redisC != nil {
				redisC.Close()
				redisC = nil
			}
		}
	}
	defer func() {
		if redisC != nil {
			log.Println("Closing Redis connection...")
			if err := redisC.Close(); err != nil {
				log.Printf("Error closing Redis connection: %v", err)
			} else {
				log.Println("Redis connection closed.")
			}
		}
	}()

	log.Println("Starting main application loop...")
	var wg sync.WaitGroup
	wg.Add(1)
	go loop(ctx, &wg)

	wg.Wait()
	log.Println("Main loop finished.")

	log.Println("Signaling shutdown completion to signal handler.")
	close(complete)

	log.Println("Waiting for signal handler to exit...")
	sigHandlerWg.Wait()

	log.Println("Exiting main.")
}

func setupPyroscope(server, appName string) {
	log.Printf("Pyroscope profiling enabled: server=%s app=%s", server, appName)
	_, err := pyroscope.Start(pyroscope.Config{
		ApplicationName: appName,
		ServerAddress:   server,
		Logger:          pyroscope.StandardLogger,
		Tags:            map[string]string{"commit": commit, "version": version},
		ProfileTypes: []pyroscope.ProfileType{
			pyroscope.ProfileCPU,
			pyroscope.ProfileAllocObjects,
			pyroscope.ProfileAllocSpace,
			pyroscope.ProfileInuseObjects,
			pyroscope.ProfileInuseSpace,
		},
	})
	if err != nil {
		log.Printf("Error starting Pyroscope: %v", err)
	} else {
		log.Println("Pyroscope profiler started.")
	}
}

func setupClickHouse(ctx context.Context, dsn string) (*sql.DB, error) {
	log.Printf("Attempting ClickHouse connection: dsn=%s", dsn)
	connectCtx, connectCancel := context.WithTimeout(ctx, 15*time.Second)
	defer connectCancel()

	db, err := sql.Open("clickhouse", dsn)
	if err != nil {
		return nil, fmt.Errorf("sql.Open failed: %w", err)
	}

	pingErr := db.PingContext(connectCtx)
	if pingErr != nil {
		db.Close()
		return nil, fmt.Errorf("failed to ping ClickHouse: %w", pingErr)
	}

	log.Println("ClickHouse connection successful.")
	// Optional: Configure connection pool settings
	// db.SetMaxOpenConns(10)
	// db.SetMaxIdleConns(5)
	// db.SetConnMaxLifetime(time.Hour)
	return db, nil
}

func setupNATS(url string) (*nats.Conn, error) {
	log.Printf("Attempting NATS connection: url=%s", url)
	nc, err := nats.Connect(url,
		nats.Timeout(10*time.Second),
		nats.Name("go_nix_simple"),
		nats.ErrorHandler(func(_ *nats.Conn, _ *nats.Subscription, err error) {
			log.Printf("NATS async error: %v", err)
		}),
		nats.DisconnectErrHandler(func(nc *nats.Conn, err error) {
			log.Printf("NATS disconnected: %v. Will attempt reconnect.", err)
		}),
		nats.ReconnectHandler(func(nc *nats.Conn) {
			log.Printf("NATS reconnected to %s", nc.ConnectedUrl())
		}),
	)
	if err != nil {
		return nil, fmt.Errorf("nats.Connect failed: %w", err)
	}
	log.Printf("NATS connection successful to: %s", nc.ConnectedUrl())
	return nc, nil
}

func setupRedis(ctx context.Context, addr, password string, db int) (*redis.Client, error) {
	log.Printf("Attempting Redis connection: addr=%s db=%d", addr, db)
	rdb := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: password,
		DB:       db,
	})

	pingCtx, pingCancel := context.WithTimeout(ctx, 10*time.Second)
	defer pingCancel()

	_, err := rdb.Ping(pingCtx).Result()
	if err != nil {
		rdb.Close()
		return nil, fmt.Errorf("redis Ping failed: %w", err)
	}

	log.Println("Redis connection successful.")
	return rdb, nil
}

func loop(ctx context.Context, wg *sync.WaitGroup) {
	defer wg.Done()
	log.Println("Loop: starting.")

	ticker := time.NewTicker(sleepTimeCst)
	defer ticker.Stop()

	hostname, _ := os.Hostname()
	if hostname == "" {
		hostname = "unknown"
	}

	for i := 0; ; i++ {
		select {
		case <-ctx.Done():
			log.Printf("Loop: context cancelled (err: %v), exiting.", ctx.Err())
			return

		case tickTime := <-ticker.C:
			log.Printf("Loop: Tick %d at %v", i, tickTime.Format(time.RFC3339))
			fmt.Printf("Hello %d from %s\n", i, hostname)
			pC.WithLabelValues("loop", "tick", "count").Inc()

			if chDB != nil {
				queryCtx, queryCancel := context.WithTimeout(ctx, 5*time.Second)
				var number uint64
				err := chDB.QueryRowContext(queryCtx, "SELECT 1").Scan(&number)
				queryCancel()
				if err != nil {
					log.Printf("Loop: Error querying ClickHouse: %v", err)
					pC.WithLabelValues("loop", "clickhouse_query", "error").Inc()
				} else {
					pC.WithLabelValues("loop", "clickhouse_query", "success").Inc()
				}
			}

			if natsC != nil && natsC.IsConnected() {
				subject := fmt.Sprintf("go_nix_simple.hello.%s", hostname)
				payload := fmt.Sprintf("Hello %d from %s at %s", i, hostname, tickTime.Format(time.RFC3339Nano))
				err := natsC.Publish(subject, []byte(payload))
				if err != nil {
					log.Printf("Loop: Error publishing to NATS: %v", err)
					pC.WithLabelValues("loop", "nats_publish", "error").Inc()
				} else {
					pC.WithLabelValues("loop", "nats_publish", "success").Inc()
				}
			}

			if redisC != nil {
				setCtx, setCancel := context.WithTimeout(ctx, 2*time.Second)
				key := fmt.Sprintf("go_nix_simple:last_hello:%s", hostname)
				val := fmt.Sprintf("%d", i)
				err := redisC.Set(setCtx, key, val, sleepTimeCst*2).Err()
				setCancel()
				if err != nil {
					log.Printf("Loop: Error setting Redis key '%s': %v", key, err)
					pC.WithLabelValues("loop", "redis_set", "error").Inc()
				} else {
					pC.WithLabelValues("loop", "redis_set", "success").Inc()
				}
			}
		}
	}
}

func initPromHandler(ctx context.Context, promPath string, promListen string) {
	log.Printf("Prometheus: Registering handler on path %s", promPath)
	mux := http.NewServeMux()
	promHandler := promhttp.HandlerFor(
		prometheus.DefaultGatherer,
		promhttp.HandlerOpts{
			EnableOpenMetrics:   promEnableOpenMetrics,
			MaxRequestsInFlight: promMaxRequestsInFlight,
		},
	)
	mux.Handle(promPath, promHandler)

	server := &http.Server{
		Addr:    promListen,
		Handler: mux,
	}

	log.Printf("Prometheus: Starting listener on %s", promListen)
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("Prometheus: Listener error: %v", err)
		} else {
			log.Println("Prometheus: Listener stopped.")
		}
	}()

	go func() {
		<-ctx.Done()
		log.Println("Prometheus: Shutdown signal received, shutting down listener...")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("Prometheus: Graceful shutdown error: %v", err)
		} else {
			log.Println("Prometheus: Listener shut down gracefully.")
		}
	}()
}

func initSignalHandler(cancel context.CancelFunc, complete <-chan struct{}, wg *sync.WaitGroup) {
	defer wg.Done()

	c := make(chan os.Signal, signalChannelSizeCst)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	log.Println("Signal: Handler started, waiting for SIGINT or SIGTERM.")

	sig := <-c
	log.Printf("Signal: Caught signal '%v', initiating shutdown.", sig)

	log.Println("Signal: Calling cancel() on main context.")
	cancel()

	log.Printf("Signal: Waiting up to %s for graceful shutdown completion...", shutdownTimeoutCst)
	timer := time.NewTimer(shutdownTimeoutCst)
	defer timer.Stop()

	select {
	case <-complete:
		log.Println("Signal: Shutdown completed gracefully. Exiting process with status 0.")
		os.Exit(0)

	case <-timer.C:
		log.Printf("Signal: Shutdown timeout (%s) reached. Forcing exit with status 1.", shutdownTimeoutCst)
		os.Exit(1)
	}
}
