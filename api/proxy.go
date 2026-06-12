package main

import (
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
)

func NewLocalProxy(target string, prefix string) http.Handler {
	upstream, err := url.Parse(target)
	if err != nil {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, err.Error(), http.StatusInternalServerError)
		})
	}

	proxy := httputil.NewSingleHostReverseProxy(upstream)
	originalDirector := proxy.Director
	proxy.Director = func(r *http.Request) {
		originalDirector(r)
		r.URL.Scheme = upstream.Scheme
		r.URL.Host = upstream.Host
		r.URL.Path = strings.TrimPrefix(r.URL.Path, prefix)
		if r.URL.Path == "" {
			r.URL.Path = "/"
		}
		r.Host = upstream.Host
	}
	proxy.ModifyResponse = func(resp *http.Response) error {
		stripFrameBlockingHeaders(resp.Header)
		return nil
	}
	return proxy
}

func stripFrameBlockingHeaders(header http.Header) {
	header.Del("X-Frame-Options")
	csp := header.Get("Content-Security-Policy")
	if csp == "" {
		return
	}
	header.Set("Content-Security-Policy", removeCSPDirective(csp, "frame-ancestors"))
}

func removeCSPDirective(csp string, directive string) string {
	parts := strings.Split(csp, ";")
	kept := parts[:0]
	for _, part := range parts {
		trimmed := strings.TrimSpace(part)
		if trimmed == "" || strings.HasPrefix(strings.ToLower(trimmed), directive) {
			continue
		}
		kept = append(kept, trimmed)
	}
	return strings.Join(kept, "; ")
}
