package main

import (
	"encoding/json"
	"net/http"
	"runtime"
	"strconv"
)

type Server struct {
	serviceProbe   ServiceProbe
	metricProbe    MetricProbe
	portalServices PortalServiceProvider
	auth           AuthConfig
}

func NewServer() *Server {
	serviceProbe := NewServiceProbe()
	return &Server{
		serviceProbe:   serviceProbe,
		metricProbe:    NewMetricProbe(),
		portalServices: NewPortalServiceProvider(),
		auth:           NewAuthConfig(),
	}
}

func (s *Server) ListenAndServe(addr string) error {
	return http.ListenAndServe(addr, s.withCORS(s.routes()))
}

func (s *Server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/auth/status", s.authStatusHandler)
	mux.HandleFunc("/health", s.healthHandler)
	mux.HandleFunc("/services", s.servicesHandler)
	mux.HandleFunc("/portal/services", s.portalServicesHandler)
	mux.HandleFunc("/metrics/simple", s.metricsHandler)
	return mux
}

func (s *Server) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if allowedOrigin(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
		} else {
			w.Header().Set("Access-Control-Allow-Origin", "http://127.0.0.1:17000")
		}
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Bridge-Token, X-XWorkspace-Token")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func allowedOrigin(origin string) bool {
	switch origin {
	case "http://127.0.0.1:17000", "http://localhost:17000", "http://127.0.0.1:3000", "https://console.svc.plus":
		return true
	default:
		return false
	}
}

func (s *Server) authStatusHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, AuthStatusResponse{Required: s.auth.Required()})
}

func (s *Server) healthHandler(w http.ResponseWriter, r *http.Request) {
	if !s.requireAuth(w, r) {
		return
	}
	services := s.serviceProbe.Probe()
	writeJSON(w, HealthResponse{
		Status:   "ok",
		Arch:     runtime.GOARCH,
		OS:       runtime.GOOS,
		CPU:      runtime.NumCPU(),
		Memory:   "unknown",
		Disk:     "unknown",
		Services: services,
		Metrics:  s.metricProbe.Probe(services),
	})
}

func (s *Server) servicesHandler(w http.ResponseWriter, r *http.Request) {
	if !s.requireAuth(w, r) {
		return
	}
	writeJSON(w, s.serviceProbe.Probe())
}

func (s *Server) portalServicesHandler(w http.ResponseWriter, r *http.Request) {
	if !s.requireAuth(w, r) {
		return
	}
	writeJSON(w, PortalServicesResponse{Services: s.portalServices.Services()})
}

func (s *Server) metricsHandler(w http.ResponseWriter, r *http.Request) {
	if !s.requireAuth(w, r) {
		return
	}
	_, _ = w.Write([]byte("xworkspace_systemd_services " + strconv.Itoa(len(s.serviceProbe.Probe())) + "\n"))
}

func (s *Server) requireAuth(w http.ResponseWriter, r *http.Request) bool {
	if s.auth.Authorize(r) {
		return true
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusUnauthorized)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": "unauthorized"})
	return false
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}
