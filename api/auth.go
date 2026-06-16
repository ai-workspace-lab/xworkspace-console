package main

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
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

type ResetAuthRequest struct {
	CurrentToken string `json:"currentToken"`
}

func generateNewToken() string {
	b := make([]byte, 32)
	rand.Read(b)
	return base64.StdEncoding.EncodeToString(b)
}

func (a *AuthConfig) ResetAuthToken(currentToken string) (string, error) {
	if !a.Required() {
		return "", fmt.Errorf("auth is not required")
	}

	valid := false
	for _, expected := range a.tokens {
		if constantTimeTokenEqual(currentToken, expected) {
			valid = true
			break
		}
	}
	if !valid {
		return "", fmt.Errorf("invalid current token")
	}

	newToken := generateNewToken()
	home, err := os.UserHomeDir()
	if err == nil {
		path1 := filepath.Join(home, ".ai_workspace_auth_token")
		path2 := filepath.Join(home, ".config", "xworkspace", "auth-token")
		os.MkdirAll(filepath.Dir(path2), 0700)
		os.WriteFile(path1, []byte(newToken), 0600)
		os.WriteFile(path2, []byte(newToken), 0600)

		openclawConfigPath := filepath.Join(home, ".openclaw", "openclaw.json")
		if b, readErr := os.ReadFile(openclawConfigPath); readErr == nil {
			var config map[string]any
			if err := json.Unmarshal(b, &config); err == nil {
				if models, ok := config["models"].(map[string]any); ok {
					if providers, ok := models["providers"].(map[string]any); ok {
						if litellm, ok := providers["litellm"].(map[string]any); ok {
							litellm["apiKey"] = newToken
							if updatedBytes, err := json.MarshalIndent(config, "", "  "); err == nil {
								os.WriteFile(openclawConfigPath, updatedBytes, 0600)
							}
						}
					}
				}
			}
		}
	}

	a.tokens = append([]string{newToken}, a.tokens...)

	// Schedule a delayed restart of related system services so the response can be sent first.
	go func() {
		time.Sleep(1 * time.Second)
		services := []string{
			"plus.svc.xworkspace.litellm",
			"plus.svc.xworkspace.openclaw",
			"plus.svc.xworkspace.hermes",
			"plus.svc.xworkspace.vault",
			"plus.svc.xworkspace.bridge",
			"plus.svc.xworkspace.qmd",
			"plus.svc.xworkspace.api",
			"plus.svc.xworkspace.console",
		}
		uid := fmt.Sprintf("gui/%d", os.Getuid())
		for _, svc := range services {
			_ = exec.Command("launchctl", "kickstart", "-k", fmt.Sprintf("%s/%s", uid, svc)).Run()
		}
	}()

	return newToken, nil
}
