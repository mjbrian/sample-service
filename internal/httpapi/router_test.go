package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func TestRoutes(t *testing.T) {
	var ready atomic.Bool
	ready.Store(true)
	h := NewRouter(&ready)

	tests := []struct {
		name, path string
		wantCode   int
		wantBody   string
	}{
		{"health", "/healthz", http.StatusOK, ""},
		{"ready", "/readyz", http.StatusOK, ""},
		{"hello default", "/api/hello", http.StatusOK, "hello world"},
		{"hello name", "/api/hello?name=matt", http.StatusOK, "hello matt"},
		{"unknown route", "/nope", http.StatusNotFound, ""},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, tc.path, nil))
			if rec.Code != tc.wantCode {
				t.Fatalf("code = %d, want %d", rec.Code, tc.wantCode)
			}
			if !strings.Contains(rec.Body.String(), tc.wantBody) {
				t.Fatalf("body = %q, want it to contain %q", rec.Body.String(), tc.wantBody)
			}
		})
	}
}

func TestReadyzWhenNotReady(t *testing.T) {
	var ready atomic.Bool // starts false
	rec := httptest.NewRecorder()
	NewRouter(&ready).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("code = %d, want 503", rec.Code)
	}
}
