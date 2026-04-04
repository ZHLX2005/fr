package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"golang.org/x/net/ipv4"
)

const (
	multicastGroup = "224.0.0.167"
	multicastPort  = 53317
	apiPort        = 53317
	protocolVersion = "2.1"
)

// MulticastDTO - sent via UDP multicast
type MulticastDTO struct {
	Alias       string `json:"alias"`
	Version     string `json:"version"`
	DeviceModel string `json:"deviceModel"`
	DeviceType  string `json:"deviceType"`
	Fingerprint string `json:"fingerprint"`
	Port        int    `json:"port"`
	Protocol    string `json:"protocol"` // "http" or "https"
	Download    bool   `json:"download"`
	Announce    bool   `json:"announce"`
	Announcement bool  `json:"announcement"`
}

// RegisterDTO - sent to /register endpoint
type RegisterDTO struct {
	Alias       string `json:"alias"`
	Version     string `json:"version"`
	DeviceModel string `json:"deviceModel"`
	DeviceType  string `json:"deviceType"`
	Fingerprint string `json:"fingerprint"`
	Port        int    `json:"port"`
	Protocol    string `json:"protocol"`
	Download    bool   `json:"download"`
}

// InfoDTO - response from /info and /register
type InfoDTO struct {
	Alias       string `json:"alias"`
	Version     string `json:"version"`
	DeviceModel string `json:"deviceModel"`
	DeviceType  string `json:"deviceType"`
	Fingerprint string `json:"fingerprint"`
	Download    bool   `json:"download"`
}

// MessageDTO - for sending messages
type MessageDTO struct {
	ID          string    `json:"id"`
	SenderID    string    `json:"senderId"`
	SenderAlias string    `json:"senderAlias"`
	Content     string    `json:"content"`
	Timestamp   time.Time `json:"timestamp"`
	Type        string    `json:"type"`
}

// Discovered device
type Device struct {
	Alias       string
	IP          string
	Port        int
	Version     string
	Fingerprint string
	LastSeen    time.Time
}

var (
	deviceID     = generateFingerprint()
	deviceAlias  = "Go Client"
	deviceModel  = "Go Client"
	deviceType   = "desktop"
	port         = apiPort
	protocol     = "http"
	download     = false
	devices      = make(map[string]*Device)
	deviceMu     sync.RWMutex
	messages     []MessageDTO
	msgMu        sync.Mutex
	shouldStop   = false
	packetConn   *ipv4.PacketConn
)

func generateFingerprint() string {
	// LocalSend uses SHA-256 hash of TLS certificate
	// For compatibility, we generate a consistent fingerprint
	h := sha256.Sum256([]byte("localsend-go-client-" + uuid.New().String()))
	return hex.EncodeToString(h[:])
}

func main() {
	reader := bufio.NewReader(os.Stdin)

	fmt.Println("=== LocalNet Go Client (LocalSend Protocol) ===")
	fmt.Printf("Device ID (fingerprint): %s\n", deviceID[:16]+"...")
	fmt.Println("Enter device alias (default: Go Client):")
	alias, _ := reader.ReadString('\n')
	alias = strings.TrimSpace(alias)
	if alias != "" {
		deviceAlias = alias
	}

	var err error
	multicastAddr := &net.UDPAddr{IP: net.ParseIP(multicastGroup), Port: multicastPort}

	// Create UDP socket for multicast
	conn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4zero, Port: 0})
	if err != nil {
		log.Fatal("Failed to create UDP socket:", err)
	}

	packetConn = ipv4.NewPacketConn(conn)
	if err := packetConn.JoinGroup(nil, multicastAddr); err != nil {
		log.Fatal("Failed to join multicast group:", err)
	}
	defer packetConn.Close()

	packetConn.SetMulticastLoopback(true)

	// Start HTTP server
	go startHTTPServer()

	// Start listening for multicast
	go listenMulticast()

	// Start announcing
	go startAnnouncing()

	// Cleanup stale devices
	go cleanupLoop()

	// Command loop
	fmt.Println("\nCommands:")
	fmt.Println("  list              - List discovered devices")
	fmt.Println("  send <id> <msg>   - Send message to device")
	fmt.Println("  messages          - Show message history")
	fmt.Println("  info              - Show this device info")
	fmt.Println("  quit              - Exit")
	fmt.Println()

	for !shouldStop {
		fmt.Print("> ")
		line, _ := reader.ReadString('\n')
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		parts := strings.SplitN(line, " ", 3)
		cmd := parts[0]

		switch cmd {
		case "list":
			listDevices()
		case "send":
			if len(parts) < 3 {
				fmt.Println("Usage: send <fingerprint> <message>")
				continue
			}
			sendToDevice(parts[1], parts[2])
		case "messages":
			showMessages()
		case "info":
			showInfo()
		case "quit", "exit":
			shouldStop = true
		default:
			fmt.Println("Unknown command")
		}
	}
}

func startHTTPServer() {
	http.HandleFunc("/api/localsend/v1/info", handleInfo)
	http.HandleFunc("/api/localsend/v2/info", handleInfo)
	http.HandleFunc("/api/localsend/v1/register", handleRegister)
	http.HandleFunc("/api/localsend/v2/register", handleRegister)
	http.HandleFunc("/api/localsend/v1/message", handleMessage)
	http.HandleFunc("/api/localsend/v2/message", handleMessage)

	addr := fmt.Sprintf(":%d", port)
	fmt.Printf("HTTP server starting on %s\n", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		if !shouldStop {
			log.Fatal(err)
		}
	}
}

func handleInfo(w http.ResponseWriter, r *http.Request) {
	senderFingerprint := r.URL.Query().Get("fingerprint")
	if senderFingerprint == deviceID {
		http.Error(w, "Self-discovered", http.StatusPreconditionFailed)
		return
	}

	info := InfoDTO{
		Alias:       deviceAlias,
		Version:     protocolVersion,
		DeviceModel: deviceModel,
		DeviceType:  deviceType,
		Fingerprint: deviceID,
		Download:    download,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var reg RegisterDTO
	body, _ := io.ReadAll(r.Body)
	r.Body.Close()

	if err := json.Unmarshal(body, &reg); err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	if reg.Fingerprint == deviceID {
		http.Error(w, "Self-discovered", http.StatusPreconditionFailed)
		return
	}

	// Extract IP from RemoteAddr
	ip := r.RemoteAddr
	if idx := strings.LastIndex(ip, ":"); idx != -1 {
		ip = ip[:idx]
	}

	deviceMu.Lock()
	devices[reg.Fingerprint] = &Device{
		Alias:       reg.Alias,
		IP:          ip,
		Port:        reg.Port,
		Version:     reg.Version,
		Fingerprint: reg.Fingerprint,
		LastSeen:    time.Now(),
	}
	deviceMu.Unlock()

	fmt.Printf("[Register] Device registered: %s (%s) via %s\n", reg.Alias, ip, r.URL.Path)

	// Respond with InfoDTO
	response := InfoDTO{
		Alias:       deviceAlias,
		Version:     protocolVersion,
		DeviceModel: deviceModel,
		DeviceType:  deviceType,
		Fingerprint: deviceID,
		Download:    download,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func handleMessage(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var msg MessageDTO
	body, _ := io.ReadAll(r.Body)
	r.Body.Close()

	if err := json.Unmarshal(body, &msg); err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	msgMu.Lock()
	messages = append(messages, msg)
	msgMu.Unlock()

	fmt.Printf("[Message] From %s: %s\n", msg.SenderAlias, msg.Content)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func listenMulticast() {
	buf := make([]byte, 65536)

	for !shouldStop {
		packetConn.SetReadDeadline(time.Now().Add(1 * time.Second))
		n, cm, addr, err := packetConn.ReadFrom(buf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue
			}
			if shouldStop {
				break
			}
			continue
		}

		// Verify this is from multicast
		if !cm.Dst.IsMulticast() {
			continue
		}

		var dto MulticastDTO
		if err := json.Unmarshal(buf[:n], &dto); err != nil {
			continue
		}

		if dto.Fingerprint == deviceID {
			continue
		}

		ip := addr.String()
		deviceMu.Lock()
		devices[dto.Fingerprint] = &Device{
			Alias:       dto.Alias,
			IP:          ip,
			Port:        dto.Port,
			Version:     dto.Version,
			Fingerprint: dto.Fingerprint,
			LastSeen:    time.Now(),
		}
		deviceMu.Unlock()

		fmt.Printf("[Discover] Found device: %s (%s) [version: %s]\n", dto.Alias, ip, dto.Version)

		// Respond to announcement
		if dto.Announce || dto.Announcement {
			go sendRegister(ip, dto.Port)
		}
	}
}

func sendRegister(ip string, remotePort int) {
	reg := RegisterDTO{
		Alias:       deviceAlias,
		Version:     protocolVersion,
		DeviceModel: deviceModel,
		DeviceType:  deviceType,
		Fingerprint: deviceID,
		Port:        port,
		Protocol:    protocol,
		Download:    download,
	}

	body, _ := json.Marshal(reg)

	// Try v2 first, then v1
	url := fmt.Sprintf("http://%s:%d/api/localsend/v2/register", ip, remotePort)
	resp, err := http.Post(url, "application/json", strings.NewReader(string(body)))
	if err != nil {
		// Fallback to v1
		url = fmt.Sprintf("http://%s:%d/api/localsend/v1/register", ip, remotePort)
		resp, err = http.Post(url, "application/json", strings.NewReader(string(body)))
	}

	if err != nil {
		fmt.Printf("[Register] Failed to register to %s: %v\n", ip, err)
		return
	}
	resp.Body.Close()
	fmt.Printf("[Register] Sent register to %s:%d (status: %d)\n", ip, remotePort, resp.StatusCode)
}

func startAnnouncing() {
	// LocalSend sends 3 announcements at 100ms, 500ms, 2000ms
	waits := []int{100, 500, 2000}

	for _, wait := range waits {
		time.Sleep(time.Duration(wait) * time.Millisecond)
		if shouldStop {
			return
		}
		sendAnnounce()
	}

	// Then continue with periodic announcements every 3 seconds
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for !shouldStop {
		<-ticker.C
		sendAnnounce()
	}
}

func sendAnnounce() {
	dto := MulticastDTO{
		Alias:        deviceAlias,
		Version:      protocolVersion,
		DeviceModel:  deviceModel,
		DeviceType:   deviceType,
		Fingerprint:  deviceID,
		Port:         port,
		Protocol:     protocol,
		Download:     download,
		Announce:     true,
		Announcement: true,
	}

	data, err := json.Marshal(dto)
	if err != nil {
		return
	}

	multicastAddr := &net.UDPAddr{IP: net.ParseIP(multicastGroup), Port: multicastPort}
	_, err = packetConn.WriteTo(data, nil, multicastAddr)
	if err != nil {
		fmt.Printf("[Announce] Send failed: %v\n", err)
	}
}

func cleanupLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for !shouldStop {
		<-ticker.C
		deviceMu.Lock()
		now := time.Now()
		for fp, dev := range devices {
			if now.Sub(dev.LastSeen) > 10*time.Second {
				fmt.Printf("[Cleanup] Device offline: %s\n", dev.Alias)
				delete(devices, fp)
			}
		}
		deviceMu.Unlock()
	}
}

func listDevices() {
	deviceMu.RLock()
	defer deviceMu.RUnlock()

	if len(devices) == 0 {
		fmt.Println("No devices discovered yet.")
		return
	}

	fmt.Println("Discovered devices:")
	for fp, dev := range devices {
		age := time.Since(dev.LastSeen).Round(time.Second)
		fmt.Printf("  [%s] %s @ %s:%d (v%s, seen %s ago)\n", fp[:8], dev.Alias, dev.IP, dev.Port, dev.Version, age)
	}
}

func sendToDevice(fingerprint, content string) {
	deviceMu.RLock()
	dev, ok := devices[fingerprint]
	deviceMu.RUnlock()

	if !ok {
		// Try partial match
		deviceMu.RLock()
		for fp, d := range devices {
			if strings.HasPrefix(fp, fingerprint) {
				dev = d
				ok = true
				break
			}
		}
		deviceMu.RUnlock()
	}

	if !ok {
		fmt.Println("Device not found. Use 'list' to see discovered devices.")
		return
	}

	msg := MessageDTO{
		ID:          uuid.New().String(),
		SenderID:    deviceID,
		SenderAlias: deviceAlias,
		Content:     content,
		Timestamp:   time.Now(),
		Type:        "text",
	}

	body, _ := json.Marshal(msg)
	url := fmt.Sprintf("http://%s:%d/api/localsend/v1/message", dev.IP, dev.Port)

	resp, err := http.Post(url, "application/json", strings.NewReader(string(body)))
	if err != nil {
		fmt.Printf("Failed to send: %v\n", err)
		return
	}
	resp.Body.Close()

	if resp.StatusCode == 200 {
		msgMu.Lock()
		messages = append(messages, msg)
		msgMu.Unlock()
		fmt.Printf("Message sent to %s\n", dev.Alias)
	} else {
		fmt.Printf("Send failed: status %d\n", resp.StatusCode)
	}
}

func showMessages() {
	msgMu.Lock()
	defer msgMu.Unlock()

	if len(messages) == 0 {
		fmt.Println("No messages yet.")
		return
	}

	fmt.Println("Message history:")
	for _, m := range messages {
		fmt.Printf("  [%s] %s: %s\n", m.Timestamp.Format("15:04:05"), m.SenderAlias, m.Content)
	}
}

func showInfo() {
	fmt.Printf("Device ID:   %s\n", deviceID)
	fmt.Printf("Alias:       %s\n", deviceAlias)
	fmt.Printf("Model:       %s\n", deviceModel)
	fmt.Printf("Type:        %s\n", deviceType)
	fmt.Printf("Port:        %d\n", port)
	fmt.Printf("Protocol:    %s\n", protocol)
	fmt.Printf("Multicast:   %s:%d\n", multicastGroup, multicastPort)
}
