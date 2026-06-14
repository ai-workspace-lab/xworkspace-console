package main

import (
	"crypto/subtle"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

type AuthConfig struct {
	tokens []string
}

func NewAuthConfig() AuthConfig {
	return AuthConfig{tokens: loadAuthTokens()}
}

func (a AuthConfig) Required() bool {
	return len(a.tokens) > 0
}

func (a AuthConfig) Authorize(r *http.Request) bool {
	if !a.Required() {
		return true
	}
	token := requestToken(r)
	if token == "" {
		return false
	}
	for _, expected := range a.tokens {
		if constantTimeTokenEqual(token, expected) {
			return true
		}
	}
	return false
}

func loadAuthTokens() []string {
	candidates := []string{
		os.Getenv("AI_WORKSPACE_AUTH_TOKEN"),
		os.Getenv("XWORKSPACE_CONSOLE_AUTH_TOKEN"),
		os.Getenv("XWORKMATE_BRIDGE_AUTH_TOKEN"),
		os.Getenv("BRIDGE_AUTH_TOKEN"),
		os.Getenv("BRIDGE_REVIEW_AUTH_TOKEN"),
		os.Getenv("INTERNAL_SERVICE_TOKEN"),
	}
	if home, err := os.UserHomeDir(); err == nil {
		candidates = append(candidates,
			readTokenFile(filepath.Join(home, ".ai_workspace_auth_token")),
			readTokenFile(filepath.Join(home, ".config", "xworkspace", "auth-token")),
		)
	}

	seen := map[string]struct{}{}
	tokens := make([]string, 0, len(candidates))
	for _, candidate := range candidates {
		token := strings.TrimSpace(candidate)
		if token == "" {
			continue
		}
		if _, ok := seen[token]; ok {
			continue
		}
		seen[token] = struct{}{}
		tokens = append(tokens, token)
	}
	return tokens
}

func readTokenFile(path string) string {
	content, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(content))
}

func requestToken(r *http.Request) string {
	header := strings.TrimSpace(r.Header.Get("Authorization"))
	if len(header) > 7 && strings.EqualFold(header[:7], "Bearer ") {
		return strings.TrimSpace(header[7:])
	}
	if header != "" {
		return header
	}
	if token := strings.TrimSpace(r.Header.Get("X-Bridge-Token")); token != "" {
		return token
	}
	return strings.TrimSpace(r.Header.Get("X-XWorkspace-Token"))
}

func constantTimeTokenEqual(actual string, expected string) bool {
	if len(actual) != len(expected) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(actual), []byte(expected)) == 1
}
