package main

import (
	"strconv"
	"strings"
)

type MetricProbe interface {
	Probe(services []Service) Metrics
}

type SystemMetricProbe struct{}

func NewMetricProbe() MetricProbe {
	return SystemMetricProbe{}
}

func (p SystemMetricProbe) Probe(services []Service) Metrics {
	return Metrics{
		ActiveSessions:  countProcesses("codex", "openclaw", "opencode", "gemini", "hermes"),
		ConnectedAgents: countConnectedAgents(services),
		ActiveModels:    countLiteLLMModels(),
		SkillsAvailable: countSkillDirs(),
		Workers:         countProcesses("codex", "openclaw", "opencode", "gemini", "hermes", "xworkmate-go-core"),
	}
}

func countConnectedAgents(services []Service) int {
	count := 0
	for _, service := range services {
		name := strings.ToLower(service.Name)
		if service.State == "active" && (strings.Contains(name, "bridge") || strings.Contains(name, "openclaw")) {
			count++
		}
	}
	return count
}

func countProcesses(names ...string) int {
	out := commandOutput("pgrep", "-af", strings.Join(names, "|"))
	if out == "" {
		return 0
	}
	count := 0
	for _, line := range strings.Split(out, "\n") {
		if strings.TrimSpace(line) != "" && !strings.Contains(line, "pgrep -af") {
			count++
		}
	}
	return count
}

func countLiteLLMModels() int {
	out := commandOutput("sh", "-lc", "curl -fsS --max-time 1 http://127.0.0.1:4000/v1/models 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get(\"data\", [])))' 2>/dev/null")
	return parseIntOrZero(out)
}

func countSkillDirs() int {
	out := commandOutput("sh", "-lc", "find \"$HOME/.openclaw/workspace/skills\" \"$HOME/.codex/skills\" \"$HOME/.agents/skills\" -name SKILL.md 2>/dev/null | wc -l")
	return parseIntOrZero(out)
}

func parseIntOrZero(value string) int {
	n, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil {
		return 0
	}
	return n
}
