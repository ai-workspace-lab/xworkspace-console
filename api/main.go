package main

import "log"

func main() {
	addr := "127.0.0.1:8788"
	log.Printf("xworkspace api listening on %s", addr)
	log.Fatal(NewServer().ListenAndServe(addr))
}
