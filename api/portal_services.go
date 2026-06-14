package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type PortalServiceProvider struct {
	file string
}

func NewPortalServiceProvider() PortalServiceProvider {
	file := os.Getenv("XWORKSPACE_PORTAL_SERVICES_FILE")
	if file == "" {
		if home, err := os.UserHomeDir(); err == nil {
			file = filepath.Join(home, ".config", "xworkspace", "portal-services.json")
		}
	}
	return PortalServiceProvider{file: file}
}

func (p PortalServiceProvider) Services() []PortalService {
	if services := p.loadFromFile(); len(services) > 0 {
		return services
	}
	return defaultPortalServices()
}

func (p PortalServiceProvider) loadFromFile() []PortalService {
	if p.file == "" {
		return nil
	}
	content, err := os.ReadFile(p.file)
	if err != nil {
		return nil
	}

	var wrapper PortalServicesResponse
	if err := json.Unmarshal(content, &wrapper); err == nil && len(wrapper.Services) > 0 {
		return normalizePortalServices(wrapper.Services)
	}

	var services []PortalService
	if err := json.Unmarshal(content, &services); err == nil && len(services) > 0 {
		return normalizePortalServices(services)
	}
	return nil
}

func normalizePortalServices(services []PortalService) []PortalService {
	normalized := make([]PortalService, 0, len(services))
	for _, service := range services {
		if service.Key == "" || service.Name == "" || service.URL == "" {
			continue
		}
		if service.OpenMode != "external" {
			service.OpenMode = "iframe"
		}
		normalized = append(normalized, service)
	}
	return normalized
}

func defaultPortalServices() []PortalService {
	return []PortalService{
		{
			Key:         "litellm",
			Name:        "LiteLLM Admin UI",
			URL:         "http://localhost:4000/ui",
			OpenMode:    "iframe",
			HealthURL:   "http://127.0.0.1:4000/ui",
			Description: "Model routing and provider administration.",
			Icon:        "chart",
			Match:       []string{"litellm", "lite"},
			Port:        4000,
			Role:        "model-router",
		},
		{
			Key:         "openclaw",
			Name:        "OpenClaw",
			URL:         "http://127.0.0.1:18789/channels",
			OpenMode:    "external",
			HealthURL:   "http://127.0.0.1:18789/channels",
			Description: "Gateway dashboard.",
			Icon:        "claw",
			Match:       []string{"openclaw", "gateway"},
			Port:        18789,
			Role:        "gateway",
		},
		{
			Key:         "vault",
			Name:        "Vault Server",
			URL:         "http://127.0.0.1:8200/ui",
			OpenMode:    "external",
			HealthURL:   "http://127.0.0.1:8200/ui",
			Description: "Vault UI.",
			Icon:        "shield",
			Match:       []string{"vault"},
			Port:        8200,
		},
		{
			Key:         "terminal",
			Name:        "Terminal",
			URL:         "http://127.0.0.1:7681",
			OpenMode:    "iframe",
			HealthURL:   "http://127.0.0.1:7681",
			Description: "Local ttyd terminal.",
			Icon:        "terminal",
			Match:       []string{"ttyd", "terminal"},
			Port:        7681,
		},
	}
}
