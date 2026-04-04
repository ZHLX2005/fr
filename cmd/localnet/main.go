package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
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

const (
	levelDebug = "🔍"
	levelInfo  = "📡"
	levelWarn  = "⚠️"
	levelError = "❌"
)

type MulticastDTO struct {
	Alias       string `json:"alias"`
	Version     string `json:"version"`
	DeviceModel string `json:"deviceModel"`
	DeviceType  string `json:"deviceType"`
	Fingerprint string `json:"fingerprint"`
	Port        int    `json:"port"`
	Protocol    string `json:"protocol"`
	Download    bool   `json:"download"`
	Announce    bool   `json:"announce"`
	Announcement bool  `json:"announcement"`
}

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

type InfoDTO struct {
	Alias       string `json:"alias"`
	Version     string `json:"version"`
	DeviceModel string `json:"deviceModel"`
	DeviceType  string `json:"deviceType"`
	Fingerprint string `json:"fingerprint"`
	Download    bool   `json:"download"`
}

type MessageDTO struct {
	ID          string    `json:"id"`
	SenderID    string    `json:"senderId"`
	SenderAlias string    `json:"senderAlias"`
	Content     string    `json:"content"`
	Timestamp   time.Time `json:"timestamp"`
	Type        string    `json:"type"`
}

type Device struct {
	Alias       string
	IP          string
	Port        int
	Version     string
	Fingerprint string
	LastSeen    time.Time
}

type LogEntry struct {
	Time    string
	Level   string
	Tag     string
	Message string
}

var (
	deviceID    = generateFingerprint()
	deviceAlias = "Go Client"
	deviceModel = "Go Client"
	deviceType  = "desktop"
	port        = apiPort
	protocol    = "http"
	download    = false
	devices     = make(map[string]*Device)
	deviceMu    sync.RWMutex
	messages    []MessageDTO
	msgMu       sync.Mutex
	shouldStop  = false
	packetConn  *ipv4.PacketConn
	udpConn     *net.UDPConn
	logs        []LogEntry
	logsMu      sync.Mutex
)

func generateFingerprint() string {
	h := sha256.Sum256([]byte("localsend-go-client-" + uuid.New().String()))
	return hex.EncodeToString(h[:])
}

func logf(level, tag, format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	timestamp := time.Now().Format("15:04:05")
	entry := LogEntry{timestamp, level, tag, msg}

	logsMu.Lock()
	logs = append(logs, entry)
	if len(logs) > 500 {
		logs = logs[1:]
	}
	logsMu.Unlock()

	fmt.Printf("[%s] %s [%s] %s\n", timestamp, level, tag, msg)
}

func logDebug(tag, format string, args ...interface{}) { logf(levelDebug, tag, format, args...) }
func logInfo(tag, format string, args ...interface{})  { logf(levelInfo, tag, format, args...) }
func logWarn(tag, format string, args ...interface{})  { logf(levelWarn, tag, format, args...) }
func logError(tag, format string, args ...interface{}) { logf(levelError, tag, format, args...) }

func printLogo() {
	fmt.Println(`
╔═══════════════════════════════════════════════╗
║       LocalNet Go Client (LocalSend)          ║
╚═══════════════════════════════════════════════╝`)
}

func main() {
	printLogo()

	reader := bufio.NewReader(os.Stdin)

	fmt.Printf("\n%sd [tag] [msg] - Debug log\n", levelDebug)
	fmt.Printf("%s [tag] [msg] - Info log\n", levelInfo)
	fmt.Printf("%s list        - Show logs\n", levelInfo)
	fmt.Printf("%s clear       - Clear logs\n", levelInfo)
	fmt.Println()

	logInfo("Init", "Fingerprint: %s", deviceID[:16]+"...")
	logInfo("Init", "Multicast: %s:%d", multicastGroup, multicastPort)
	logInfo("Init", "HTTP Port: %d", apiPort)

	fmt.Println("Enter device alias (default: Go Client):")
	alias, _ := reader.ReadString('\n')
	alias = strings.TrimSpace(alias)
	if alias != "" {
		deviceAlias = alias
	}
	logInfo("Init", "Alias: %s", deviceAlias)

	// List interfaces
	logInfo("Init", "=== Network Interfaces ===")
	ifaces, _ := net.Interfaces()
	activeIfaces := []net.Interface{}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, addr := range addrs {
			if ip, ok := addr.(*net.IPNet); ok && ip.IP.To4() != nil {
				logInfo("Init", "  %s: %s", iface.Name, ip.IP.String())
				activeIfaces = append(activeIfaces, iface)
			}
		}
	}

	// Create UDP socket
	logInfo("Init", "Creating UDP socket...")
	addr := &net.UDPAddr{IP: net.IPv4zero, Port: 0}
	conn, err := net.ListenUDP("udp", addr)
	if err != nil {
		logError("Init", "Failed to create UDP socket: %v", err)
		os.Exit(1)
	}
	udpConn = conn

	// Wrap with ipv4 PacketConn for multicast support
	packetConn = ipv4.NewPacketConn(conn)
	packetConn.SetMulticastLoopback(true)

	// Join multicast group on each interface
	multicastAddr := &net.UDPAddr{IP: net.ParseIP(multicastGroup), Port: multicastPort}
	for _, iface := range activeIfaces {
		if err := packetConn.JoinGroup(&iface, multicastAddr); err != nil {
			logWarn("Init", "Failed to join multicast on %s: %v", iface.Name, err)
		} else {
			logInfo("Init", "✓ Joined multicast on %s", iface.Name)
		}
	}

	// Start HTTP server
	logInfo("Init", "Starting HTTP server...")
	go startHTTPServer()
	time.Sleep(100 * time.Millisecond)

	// Start multicast listener
	logInfo("Init", "Starting multicast listener...")
	go listenMulticast()

	// Start HTTP scanner for fallback discovery
	logInfo("Init", "Starting HTTP subnet scanner...")
	go startHttpScanner()

	// Start announcer
	logInfo("Init", "Starting announcements...")
	go startAnnouncing()

	// Cleanup stale devices
	go cleanupLoop()

	fmt.Println("\nCommands:")
	fmt.Println("  list              - List discovered devices")
	fmt.Println("  send <id> <msg>  - Send message")
	fmt.Println("  logs              - Show logs")
	fmt.Println("  clear             - Clear logs")
	fmt.Println("  info              - Device info")
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
		case "logs":
			printLogs()
		case "clear":
			clearLogs()
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
	logInfo("HTTP", "HTTP server listening on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		if !shouldStop {
			logError("HTTP", "Server error: %v", err)
		}
	}
}

func handleInfo(w http.ResponseWriter, r *http.Request) {
	logDebug("HTTP", "← GET %s (from %s)", r.URL.Path, r.RemoteAddr)

	senderFingerprint := r.URL.Query().Get("fingerprint")
	if senderFingerprint == deviceID {
		logWarn("HTTP", "Ignoring self-request")
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
	logDebug("HTTP", "→ /info response: %+v", info)
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	logDebug("HTTP", "← POST %s (from %s)", r.URL.Path, r.RemoteAddr)

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var reg RegisterDTO
	body, _ := io.ReadAll(r.Body)
	r.Body.Close()

	logDebug("HTTP", "Register data: %s", string(body))

	if err := json.Unmarshal(body, &reg); err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	if reg.Fingerprint == deviceID {
		logWarn("HTTP", "Ignoring self-register")
		http.Error(w, "Self-discovered", http.StatusPreconditionFailed)
		return
	}

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

	logInfo("HTTP", "✓ Device registered: %s (%s:%d) [v%s]", reg.Alias, ip, reg.Port, reg.Version)

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
	logDebug("HTTP", "← POST %s (from %s)", r.URL.Path, r.RemoteAddr)

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var msg MessageDTO
	body, _ := io.ReadAll(r.Body)
	r.Body.Close()

	logDebug("HTTP", "Message data: %s", string(body))

	if err := json.Unmarshal(body, &msg); err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	msgMu.Lock()
	messages = append(messages, msg)
	msgMu.Unlock()

	logInfo("Message", "Received from %s: %s", msg.SenderAlias, msg.Content)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func listenMulticast() {
	buf := make([]byte, 65536)
	receiveCount := 0
	lastLog := time.Now()

	logInfo("Multicast", "Listening on %s:%d", multicastGroup, multicastPort)

	for !shouldStop {
		packetConn.SetReadDeadline(time.Now().Add(1 * time.Second))
		n, cm, addr, err := packetConn.ReadFrom(buf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				if receiveCount == 0 && time.Since(lastLog) > 5*time.Second {
					logDebug("Multicast", "Waiting for UDP data... (no data received yet)")
					lastLog = time.Now()
				}
				continue
			}
			if shouldStop {
				break
			}
			logWarn("Multicast", "Read error: %v", err)
			continue
		}

		receiveCount++
		dataStr := string(buf[:n])
		addrStr := addr.String()
		isMulticast := cm.Dst.IsMulticast()

		logInfo("Multicast", "★ UDP #%d: %d bytes from %s (multicast=%v)", receiveCount, n, addrStr, isMulticast)
		if n < 500 {
			logDebug("Multicast", "  Data: %s", dataStr)
		}

		if !isMulticast {
			logDebug("Multicast", "  Ignoring non-multicast packet")
			continue
		}

		var dto MulticastDTO
		if err := json.Unmarshal(buf[:n], &dto); err != nil {
			logWarn("Multicast", "Failed to parse: %v", err)
			continue
		}

		if dto.Fingerprint == deviceID {
			logDebug("Multicast", "Ignoring own broadcast")
			continue
		}

		deviceMu.Lock()
		devices[dto.Fingerprint] = &Device{
			Alias:       dto.Alias,
			IP:          addrStr,
			Port:        dto.Port,
			Version:     dto.Version,
			Fingerprint: dto.Fingerprint,
			LastSeen:    time.Now(),
		}
		deviceMu.Unlock()

		logInfo("Multicast", "✓ Discovered: %s (%s) [v%s, port:%d]", dto.Alias, addrStr, dto.Version, dto.Port)

		if dto.Announce || dto.Announcement {
			go sendRegister(addrStr, dto.Port)
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
	logDebug("Register", "→ POST /register to %s:%d", ip, remotePort)

	url := fmt.Sprintf("http://%s:%d/api/localsend/v2/register", ip, remotePort)
	resp, err := http.Post(url, "application/json", strings.NewReader(string(body)))
	if err != nil {
		url = fmt.Sprintf("http://%s:%d/api/localsend/v1/register", ip, remotePort)
		resp, err = http.Post(url, "application/json", strings.NewReader(string(body)))
	}

	if err != nil {
		logError("Register", "✗ Register failed: %v", err)
		return
	}
	resp.Body.Close()
	logInfo("Register", "✓ Register response (status: %d)", resp.StatusCode)
}

func startAnnouncing() {
	waits := []int{100, 500, 2000}
	logInfo("Announce", "Starting announcements...")

	for _, wait := range waits {
		time.Sleep(time.Duration(wait) * time.Millisecond)
		if shouldStop {
			return
		}
		sendAnnounce()
	}

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
		logError("Announce", "Marshal failed: %v", err)
		return
	}

	dataStr := string(data)
	multicastAddr := &net.UDPAddr{IP: net.ParseIP(multicastGroup), Port: multicastPort}

	// Send on each interface
	ifaces, _ := net.Interfaces()
	sent := 0
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}

		// Use the raw connection for sending to set the outgoing interface
		pc := ipv4.NewPacketConn(udpConn)
		if err := pc.SetMulticastInterface(&iface); err != nil {
			logWarn("Announce", "Failed to set interface %s: %v", iface.Name, err)
		}

		n, err := pc.WriteTo(data, nil, multicastAddr)
		if err != nil {
			logWarn("Announce", "Send failed on %s: %v", iface.Name, err)
		} else {
			sent++
			logDebug("Announce", "→ UDP [%s]: %s (%d bytes)", iface.Name, dataStr, n)
		}
	}

	if sent > 0 {
		logInfo("Announce", "✓ Announced on %d interfaces", sent)
	} else {
		logError("Announce", "✗ All announcements failed")
	}
}

func startHttpScanner() {
	// Scan subnet periodically
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	// Initial scan after 1 second
	time.Sleep(1 * time.Second)
	scanSubnet()

	for !shouldStop {
		<-ticker.C
		scanSubnet()
	}
}

func scanSubnet() {
	// Get our IP to determine subnet
	var localIP string
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, addr := range addrs {
			if ip, ok := addr.(*net.IPNet); ok && ip.IP.To4() != nil {
				if strings.HasPrefix(ip.IP.String(), "192.168.") || strings.HasPrefix(ip.IP.String(), "10.") {
					localIP = ip.IP.String()
					break
				}
			}
		}
	}

	if localIP == "" {
		logWarn("HTTP", "No suitable IP for subnet scan")
		return
	}

	// Extract subnet prefix
	parts := strings.Split(localIP, ".")
	subnetPrefix := strings.Join(parts[:3], ".")
	logInfo("HTTP", "Scanning subnet %s.0/24 from IP %s", subnetPrefix, localIP)

	// Scan all IPs in parallel (limited concurrency)
	sem := make(chan struct{}, 50)
	var wg sync.WaitGroup
	found := 0

	for i := 1; i < 256; i++ {
		ip := fmt.Sprintf("%s.%d", subnetPrefix, i)
		if ip == localIP {
			continue // Skip self
		}

		wg.Add(1)
		go func(ip string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			if device := httpDiscover(ip); device != nil {
				deviceMu.Lock()
				existing := devices[device.Fingerprint]
				if existing == nil || time.Since(existing.LastSeen) > 5*time.Second {
					devices[device.Fingerprint] = device
					logInfo("HTTP", "✓ Discovered via HTTP: %s (%s) [v%s]", device.Alias, device.IP, device.Version)
					found++
				}
				deviceMu.Unlock()
			}
		}(ip)
	}

	wg.Wait()
	if found > 0 {
		logInfo("HTTP", "HTTP scan found %d new devices", found)
	}
}

func httpDiscover(ip string) *Device {
	// Try v2 first, then v1
	for _, version := range []string{"v2", "v1"} {
		url := fmt.Sprintf("http://%s:%d/api/localsend/%s/info?fingerprint=%s", ip, port, version, deviceID)
		resp, err := http.Get(url)
		if err != nil {
			continue
		}
		defer resp.Body.Close()

		if resp.StatusCode != 200 {
			continue
		}

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			continue
		}

		var info InfoDTO
		if err := json.Unmarshal(body, &info); err != nil {
			continue
		}

		if info.Fingerprint == deviceID {
			continue // Self
		}

		return &Device{
			Alias:       info.Alias,
			IP:          ip,
			Port:        port,
			Version:     info.Version,
			Fingerprint: info.Fingerprint,
			LastSeen:   time.Now(),
		}
	}
	return nil
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
				logInfo("Cleanup", "Device offline: %s", dev.Alias)
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
		fmt.Println("No devices discovered")
		return
	}

	fmt.Println("Discovered devices:")
	for fp, dev := range devices {
		age := time.Since(dev.LastSeen).Round(time.Second)
		fmt.Printf("  [%s] %s @ %s:%d (v%s, %s ago)\n", fp[:8], dev.Alias, dev.IP, dev.Port, dev.Version, age)
	}
}

func sendToDevice(fingerprint, content string) {
	deviceMu.RLock()
	dev, ok := devices[fingerprint]
	deviceMu.RUnlock()

	if !ok {
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
		fmt.Println("Device not found")
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
	logInfo("Message", "Sending to %s (%s:%d)", dev.Alias, dev.IP, dev.Port)
	logDebug("Message", "→ POST /message: %s", string(body))

	url := fmt.Sprintf("http://%s:%d/api/localsend/v1/message", dev.IP, dev.Port)
	resp, err := http.Post(url, "application/json", strings.NewReader(string(body)))
	if err != nil {
		logError("Message", "✗ Send failed: %v", err)
		fmt.Printf("Send failed: %v\n", err)
		return
	}
	resp.Body.Close()

	if resp.StatusCode == 200 {
		msgMu.Lock()
		messages = append(messages, msg)
		msgMu.Unlock()
		logInfo("Message", "✓ Message sent")
		fmt.Println("Message sent")
	} else {
		logWarn("Message", "✗ Send failed: status %d", resp.StatusCode)
		fmt.Printf("Send failed: status %d\n", resp.StatusCode)
	}
}

func printLogs() {
	logsMu.Lock()
	defer logsMu.Unlock()

	if len(logs) == 0 {
		fmt.Println("No logs")
		return
	}

	fmt.Println("Logs:")
	for _, entry := range logs {
		fmt.Printf("  [%s] %s [%s] %s\n", entry.Time, entry.Level, entry.Tag, entry.Message)
	}
}

func clearLogs() {
	logsMu.Lock()
	logs = nil
	logsMu.Unlock()
	fmt.Println("Logs cleared")
}

func showInfo() {
	fmt.Println("Device Info:")
	fmt.Printf("  ID:       %s\n", deviceID)
	fmt.Printf("  Alias:    %s\n", deviceAlias)
	fmt.Printf("  Model:    %s\n", deviceModel)
	fmt.Printf("  Type:     %s\n", deviceType)
	fmt.Printf("  Port:     %d\n", port)
	fmt.Printf("  Protocol: %s\n", protocol)
	fmt.Printf("  Multicast: %s:%d\n", multicastGroup, multicastPort)
}
