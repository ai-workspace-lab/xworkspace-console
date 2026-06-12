package main

type Service struct {
	Name   string `json:"name"`
	State  string `json:"state"`
	Unit   string `json:"unit"`
	Detail string `json:"detail,omitempty"`
	Port   int    `json:"port,omitempty"`
	URL    string `json:"url,omitempty"`
}

type HealthResponse struct {
	Status   string    `json:"status"`
	Arch     string    `json:"arch"`
	OS       string    `json:"os"`
	CPU      int       `json:"cpu"`
	Memory   string    `json:"memory"`
	Disk     string    `json:"disk"`
	Services []Service `json:"services"`
	Metrics  Metrics   `json:"metrics"`
}

type Metrics struct {
	ActiveSessions  int `json:"activeSessions"`
	ConnectedAgents int `json:"connectedAgents"`
	ActiveModels    int `json:"activeModels"`
	SkillsAvailable int `json:"skillsAvailable"`
	Workers         int `json:"workers"`
}
