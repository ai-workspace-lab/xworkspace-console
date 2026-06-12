package main

import (
	"os/exec"
	"strings"
)

func commandState(name string, args ...string) string {
	out := commandOutput(name, args...)
	if out == "" {
		return ""
	}
	return strings.TrimSpace(out)
}

func commandOutput(name string, args ...string) string {
	cmd := exec.Command(name, args...)
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}
