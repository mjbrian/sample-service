package httpapi

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"sync/atomic"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	requests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total", Help: "HTTP requests by route and status code.",
	}, []string{"route", "code"})
	duration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name: "http_request_duration_seconds", Help: "HTTP request latency.",
		Buckets: prometheus.DefBuckets,
	}, []string{"route"})

	// hold keeps debug allocations alive so the memory stays in use.
	hold [][]byte
)

// NewRouter returns the service's HTTP handler. ready controls /readyz.
func NewRouter(ready *atomic.Bool) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !ready.Load() {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	mux.Handle("GET /metrics", promhttp.Handler())
	mux.Handle("GET /api/hello", instrument("/api/hello", http.HandlerFunc(hello)))

	// Only for break drills. Never set DEBUG_ENDPOINTS in production.
	if os.Getenv("DEBUG_ENDPOINTS") == "true" {
		mux.HandleFunc("GET /debug/alloc", func(w http.ResponseWriter, r *http.Request) {
			mb, _ := strconv.Atoi(r.URL.Query().Get("mb"))
			buf := make([]byte, mb<<20)
			for i := range buf {
				buf[i] = 1 // touch every page so the memory is really used
			}
			hold = append(hold, buf)
			_, _ = fmt.Fprintf(w, "holding %d allocations\n", len(hold))
		})
	}
	return mux
}

func hello(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("name")
	if name == "" {
		name = "world"
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"message": "hello " + name})
}

// statusRecorder remembers the status code a handler wrote.
type statusRecorder struct {
	http.ResponseWriter
	code int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.code = code
	s.ResponseWriter.WriteHeader(code)
}

// instrument records a count and a duration for every request.
func instrument(route string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, code: http.StatusOK}
		next.ServeHTTP(rec, r)
		duration.WithLabelValues(route).Observe(time.Since(start).Seconds())
		requests.WithLabelValues(route, strconv.Itoa(rec.code)).Inc()
	})
}
