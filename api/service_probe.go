package main

import (
	"net"
	"strconv"
	"time"
)

type ServiceProbe interface {
	Probe() []Service
}

type serviceProbeConfig struct {
	Name  string
	Units []string
	Port  int
	URL   string
}

type SystemServiceProbe struct {
	services []serviceProbeConfig
}

func NewServiceProbe() ServiceProbe {
	return SystemServiceProbe{
		services: []serviceProbeConfig{
			{Name: "XWorkspace Console", Units: []string{"xworkspace-console.service"}, Port: 17000, URL: "http://127.0.0.1:17000"},
			{Name: "OpenClaw Gateway", Units: []string{"xworkspace-openclaw.service", "openclaw-gateway.service"}, Port: 18789, URL: "http://127.0.0.1:18789/channels"},
			{Name: "XWorkmate Bridge", Units: []string{"xworkspace-bridge.service", "xworkmate-bridge.service"}, Port: 8787, URL: "http://127.0.0.1:8787/api/ping"},
			{Name: "LiteLLM", Units: []string{"xworkspace-litellm.service", "litellm-proxy.service"}, Port: 4000, URL: "http://127.0.0.1:4000/ui"},
			{Name: "Vault", Units: []string{"xworkspace-vault.service", "vault.service"}, Port: 8200, URL: "http://127.0.0.1:8200/ui/"},
			{Name: "Terminal", Units: []string{"xworkspace-ttyd.service", "ttyd.service"}, Port: 7681, URL: "http://127.0.0.1:7681"},
		},
	}
}

func (p SystemServiceProbe) Probe() []Service {
	services := make([]Service, 0, len(p.services))
	for _, config := range p.services {
		unit, state := firstSystemdUnit(config.Units)
		portOpen := config.Port > 0 && isPortOpen("127.0.0.1", config.Port)
		if state == "" && portOpen {
			state = "active"
		} else if state == "" {
			state = "inactive"
		}
		services = append(services, Service{
			Name:   config.Name,
			Unit:   unit,
			State:  state,
			Detail: probeDetail(unit, portOpen),
			Port:   config.Port,
			URL:    config.URL,
		})
	}
	return services
}

func firstSystemdUnit(units []string) (string, string) {
	for _, unit := range units {
		if state := commandState("systemctl", "is-active", unit); state != "" && state != "unknown" {
			return unit, state
		}
		if state := commandState("systemctl", "--user", "is-active", unit); state != "" && state != "unknown" {
			return unit, state
		}
	}
	for _, unit := range units {
		if state := commandState("systemctl", "is-enabled", unit); state != "" && state != "unknown" {
			return unit, ""
		}
		if state := commandState("systemctl", "--user", "is-enabled", unit); state != "" && state != "unknown" {
			return unit, ""
		}
	}
	return "", ""
}

func probeDetail(unit string, portOpen bool) string {
	if unit == "" && portOpen {
		return "port open"
	}
	if portOpen {
		return "systemd + port open"
	}
	return "systemd"
}

func isPortOpen(host string, port int) bool {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(port)), 300*time.Millisecond)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}
