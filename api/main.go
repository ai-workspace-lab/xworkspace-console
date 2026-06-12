package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
)

type Service struct {
	Name   string `json:"name"`
	State  string `json:"state"`
	Unit   string `json:"unit"`
	Detail string `json:"detail,omitempty"`
}

type HealthResponse struct {
	Status   string    `json:"status"`
	Arch     string    `json:"arch"`
	OS       string    `json:"os"`
	CPU      int       `json:"cpu"`
	Memory   string    `json:"memory"`
	Disk     string    `json:"disk"`
	Services []Service `json:"services"`
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/services", servicesHandler)
	mux.HandleFunc("/metrics/simple", metricsHandler)

	addr := "127.0.0.1:8788"
	log.Printf("xworkspace api listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, withCORS(mux)))
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "http://127.0.0.1:17000")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, HealthResponse{
		Status:   "ok",
		Arch:     runtime.GOARCH,
		OS:       runtime.GOOS,
		CPU:      runtime.NumCPU(),
		Memory:   "unknown",
		Disk:     "unknown",
		Services: probeServices(),
	})
}

func servicesHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, probeServices())
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	_, _ = w.Write([]byte("xworkspace_systemd_services " + strconv.Itoa(len(probeServices())) + "\n"))
}

func probeServices() []Service {
	units := []string{
		"xworkspace-console.service",
		"xworkspace-openclaw.service",
		"xworkspace-bridge.service",
		"xworkspace-litellm.service",
		"xworkspace-vault.service",
	}
	services := make([]Service, 0, len(units))
	for _, unit := range units {
		state := commandState("systemctl", "--user", "is-active", unit)
		if state == "" {
			state = "unknown"
		}
		services = append(services, Service{
			Name:  strings.TrimSuffix(unit, ".service"),
			Unit:  unit,
			State: state,
		})
	}
	return services
}

func commandState(name string, args ...string) string {
	cmd := exec.Command(name, args...)
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}
