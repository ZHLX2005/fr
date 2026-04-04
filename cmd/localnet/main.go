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

// Log levels
const (
	levelDebug = "🔍"
	levelInfo  = "📡"
	levelWarn  = "⚠️"
	levelError = "❌"
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

// LogEntry for in-memory logging
type LogEntry struct {
	Time    string
	Level   string
	Tag     string
	Message string
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
	logs         []LogEntry
	logsMu       sync.Mutex
)

func generateFingerprint() string {
	h := sha256.Sum256([]byte("localsend-go-client-" + uuid.New().String()))
	return hex.EncodeToString(h[:])
}

func logf(level, tag, format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	timestamp := time.Now().Format("15:04:05")
	entry := LogEntry{
		Time:    timestamp,
		Level:   level,
		Tag:     tag,
		Message: msg,
	}

	logsMu.Lock()
	logs = append(logs, entry)
	if len(logs) > 500 {
		logs = logs[1:]
	}
	logsMu.Unlock()

	// Also print to stdout
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

	fmt.Printf("\n%sd [tag] [msg] - 发送调试日志\n", levelDebug)
	fmt.Printf("%s [tag] [msg] - 发送信息日志\n", levelInfo)
	fmt.Printf("%s [tag] [msg] - 发送警告日志\n", levelWarn)
	fmt.Printf("%s list        - 查看日志历史\n", levelInfo)
	fmt.Printf("%s clear       - 清除日志\n", levelInfo)
	fmt.Println()

	logInfo("Init", "设备指纹: %s", deviceID[:16]+"...")
	logInfo("Init", "多播地址: %s:%d", multicastGroup, multicastPort)
	logInfo("Init", "HTTP 端口: %d", apiPort)

	fmt.Println("Enter device alias (default: Go Client):")
	alias, _ := reader.ReadString('\n')
	alias = strings.TrimSpace(alias)
	if alias != "" {
		deviceAlias = alias
	}
	logInfo("Init", "设备别名: %s", deviceAlias)

	var err error
	multicastAddr := &net.UDPAddr{IP: net.ParseIP(multicastGroup), Port: multicastPort}

	// Create UDP socket for multicast
	logInfo("Init", "创建 UDP socket...")
	conn, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4zero, Port: 0})
	if err != nil {
		logError("Init", "创建 UDP socket 失败: %v", err)
		os.Exit(1)
	}

	packetConn = ipv4.NewPacketConn(conn)
	if err := packetConn.JoinGroup(nil, multicastAddr); err != nil {
		logError("Init", "加入多播组失败: %v", err)
		os.Exit(1)
	}
	logInfo("Init", "✓ 成功加入多播组 %s", multicastAddr.String())

	packetConn.SetMulticastLoopback(true)

	// Start HTTP server
	logInfo("Init", "启动 HTTP 服务器...")
	go startHTTPServer()
	time.Sleep(100 * time.Millisecond) // Wait for server to start

	// Start listening for multicast
	logInfo("Init", "启动多播监听...")
	go listenMulticast()

	// Start announcing
	logInfo("Init", "开始广播...")
	go startAnnouncing()

	// Cleanup stale devices
	go cleanupLoop()

	// Command loop
	fmt.Println("\n命令:")
	fmt.Println("  list              - 查看发现的设备")
	fmt.Println("  send <id> <msg>  - 发送消息")
	fmt.Println("  logs              - 查看日志")
	fmt.Println("  clear             - 清除日志")
	fmt.Println("  info              - 本机信息")
	fmt.Println("  quit              - 退出")
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
				fmt.Println("用法: send <fingerprint> <message>")
				continue
			}
			sendToDevice(parts[1], parts[2])
		case "logs":
			printLogs()
		case "clear":
			clearLogs()
		case "info":
			showInfo()
		case "d", "i", "w", "e":
			// Manual log entry for testing
			if len(parts) < 3 {
				fmt.Println("用法:", cmd, "<tag> <message>")
				continue
			}
			switch cmd {
			case "d":
				logDebug(parts[1], "%s", parts[2])
			case "i":
				logInfo(parts[1], "%s", parts[2])
			case "w":
				logWarn(parts[1], "%s", parts[2])
			case "e":
				logError(parts[1], "%s", parts[2])
			}
		case "quit", "exit":
			shouldStop = true
		default:
			fmt.Println("未知命令。可用命令: list, send, logs, clear, info, quit")
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
	logInfo("HTTP", "HTTP 服务器监听 %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		if !shouldStop {
			logError("HTTP", "服务器错误: %v", err)
		}
	}
}

func handleInfo(w http.ResponseWriter, r *http.Request) {
	logDebug("HTTP", "← GET %s (from %s)", r.URL.Path, r.RemoteAddr)

	senderFingerprint := r.URL.Query().Get("fingerprint")
	if senderFingerprint == deviceID {
		logWarn("HTTP", "忽略自请求")
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
	logDebug("HTTP", "→ 响应 /info: %+v", info)
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	logDebug("HTTP", "← POST %s (from %s)", r.URL.Path, r.RemoteAddr)

	if r.Method != http.MethodPost {
		logWarn("HTTP", "不支持的方法: %s", r.Method)
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var reg RegisterDTO
	body, _ := io.ReadAll(r.Body)
	r.Body.Close()

	logDebug("HTTP", "注册数据: %s", string(body))

	if err := json.Unmarshal(body, &reg); err != nil {
		logError("HTTP", "解析注册请求失败: %v", err)
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	if reg.Fingerprint == deviceID {
		logWarn("HTTP", "忽略自注册")
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

	logInfo("HTTP", "✓ 设备注册: %s (%s:%d) [v%s]", reg.Alias, ip, reg.Port, reg.Version)

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
	logDebug("HTTP", "→ 响应 /register: %+v", response)
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

	logDebug("HTTP", "消息数据: %s", string(body))

	if err := json.Unmarshal(body, &msg); err != nil {
		logError("HTTP", "解析消息失败: %v", err)
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	msgMu.Lock()
	messages = append(messages, msg)
	msgMu.Unlock()

	logInfo("Message", "收到消息 from %s: %s", msg.SenderAlias, msg.Content)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func listenMulticast() {
	buf := make([]byte, 65536)

	logInfo("Multicast", "开始监听多播 %s:%d", multicastGroup, multicastPort)

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
			logWarn("Multicast", "读取错误: %v", err)
			continue
		}

		// Verify this is from multicast
		if !cm.Dst.IsMulticast() {
			logDebug("Multicast", "忽略非多播数据 from %s", addr.String())
			continue
		}

		dataStr := string(buf[:n])
		logDebug("Multicast", "← UDP 数据 (%d bytes) from %s: %s", n, addr.String(), dataStr)

		var dto MulticastDTO
		if err := json.Unmarshal(buf[:n], &dto); err != nil {
			logWarn("Multicast", "解析 UDP 数据失败: %v", err)
			continue
		}

		if dto.Fingerprint == deviceID {
			logDebug("Multicast", "忽略自己的广播")
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

		logInfo("Multicast", "✓ 发现设备: %s (%s) [v%s, port:%d]", dto.Alias, ip, dto.Version, dto.Port)

		// Respond to announcement
		if dto.Announce || dto.Announcement {
			logDebug("Multicast", "收到 announcement，发送 register 到 %s:%d", ip, dto.Port)
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
	logDebug("Register", "→ POST /register to %s:%d: %s", ip, remotePort, string(body))

	// Try v2 first, then v1
	url := fmt.Sprintf("http://%s:%d/api/localsend/v2/register", ip, remotePort)
	resp, err := http.Post(url, "application/json", strings.NewReader(string(body)))
	if err != nil {
		// Fallback to v1
		url = fmt.Sprintf("http://%s:%d/api/localsend/v1/register", ip, remotePort)
		resp, err = http.Post(url, "application/json", strings.NewReader(string(body)))
	}

	if err != nil {
		logError("Register", "✗ 注册失败: %v", err)
		return
	}
	resp.Body.Close()
	logInfo("Register", "✓ 注册响应 (status: %d)", resp.StatusCode)
}

func startAnnouncing() {
	// LocalSend sends 3 announcements at 100ms, 500ms, 2000ms
	waits := []int{100, 500, 2000}

	logInfo("Announce", "开始广播 announcement...")

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
		logError("Announce", "序列化广播数据失败: %v", err)
		return
	}

	dataStr := string(data)
	logDebug("Announce", "→ UDP 广播: %s", dataStr)

	multicastAddr := &net.UDPAddr{IP: net.ParseIP(multicastGroup), Port: multicastPort}
	n, err := packetConn.WriteTo(data, nil, multicastAddr)
	if err != nil {
		logError("Announce", "✗ UDP 广播发送失败: %v", err)
	} else {
		logInfo("Announce", "✓ UDP 广播已发送 (%d bytes)", n)
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
				logInfo("Cleanup", "设备离线: %s", dev.Alias)
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
		fmt.Println("未发现设备")
		return
	}

	fmt.Println("发现的设备:")
	for fp, dev := range devices {
		age := time.Since(dev.LastSeen).Round(time.Second)
		fmt.Printf("  [%s] %s @ %s:%d (v%s, %s前)\n", fp[:8], dev.Alias, dev.IP, dev.Port, dev.Version, age)
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
		fmt.Println("设备未找到。使用 'list' 查看已发现设备")
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
	logInfo("Message", "发送消息到 %s (%s:%d)", dev.Alias, dev.IP, dev.Port)
	logDebug("Message", "→ POST /message: %s", string(body))

	url := fmt.Sprintf("http://%s:%d/api/localsend/v1/message", dev.IP, dev.Port)
	resp, err := http.Post(url, "application/json", strings.NewReader(string(body)))
	if err != nil {
		logError("Message", "✗ 发送失败: %v", err)
		fmt.Printf("发送失败: %v\n", err)
		return
	}
	resp.Body.Close()

	if resp.StatusCode == 200 {
		msgMu.Lock()
		messages = append(messages, msg)
		msgMu.Unlock()
		logInfo("Message", "✓ 消息已发送")
		fmt.Printf("消息已发送\n")
	} else {
		logWarn("Message", "✗ 发送失败，状态码: %d", resp.StatusCode)
		fmt.Printf("发送失败，状态码: %d\n", resp.StatusCode)
	}
}

func printLogs() {
	logsMu.Lock()
	defer logsMu.Unlock()

	if len(logs) == 0 {
		fmt.Println("暂无日志")
		return
	}

	fmt.Println("日志历史:")
	for _, entry := range logs {
		fmt.Printf("  [%s] %s [%s] %s\n", entry.Time, entry.Level, entry.Tag, entry.Message)
	}
}

func clearLogs() {
	logsMu.Lock()
	logs = nil
	logsMu.Unlock()
	fmt.Println("日志已清除")
}

func showInfo() {
	fmt.Println("本机信息:")
	fmt.Printf("  设备 ID:   %s\n", deviceID)
	fmt.Printf("  别名:      %s\n", deviceAlias)
	fmt.Printf("  模型:      %s\n", deviceModel)
	fmt.Printf("  类型:      %s\n", deviceType)
	fmt.Printf("  端口:      %d\n", port)
	fmt.Printf("  协议:      %s\n", protocol)
	fmt.Printf("  多播地址:  %s:%d\n", multicastGroup, multicastPort)
}
