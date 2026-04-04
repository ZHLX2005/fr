package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
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
)

const (
	levelDebug = "🔍"
	levelInfo  = "📡"
	levelWarn  = "⚠️"
	levelError = "❌"
)

type Device struct {
	Alias    string
	IP       string
	Port     int
	ID       string
	LastSeen time.Time
}

var (
	deviceID    = generateFingerprint()
	deviceAlias = "Go Client"
	deviceModel = "Go Client"
	deviceType  = "desktop"
	port        = apiPort
	devices     = make(map[string]*Device)
	deviceMu    sync.RWMutex
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

type LogEntry struct {
	Time    string
	Level   string
	Tag     string
	Message string
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
║       LocalNet Go Client (any_share style)   ║
╚═══════════════════════════════════════════════╝`)
}

func main() {
	printLogo()

	reader := bufio.NewReader(os.Stdin)

	fmt.Printf("\n%s list        - Show discovered devices\n", levelInfo)
	fmt.Printf("%s logs        - Show logs\n", levelInfo)
	fmt.Printf("%s clear       - Clear logs\n", levelInfo)
	fmt.Printf("%s quit        - Exit\n", levelInfo)
	fmt.Println()

	logInfo("Init", "Device ID: %s", deviceID[:16]+"...")
	logInfo("Init", "Device Alias: %s", deviceAlias)
	logInfo("Init", "Multicast: %s:%d", multicastGroup, multicastPort)
	logInfo("Init", "HTTP Port: %d", apiPort)

	// 创建 UDP socket
	logInfo("Init", "Creating UDP socket...")
	addr := &net.UDPAddr{IP: net.IPv4zero, Port: 0}
	conn, err := net.ListenUDP("udp", addr)
	if err != nil {
		logError("Init", "Failed to create UDP socket: %v", err)
		os.Exit(1)
	}
	udpConn = conn

	// 包装为 ipv4 PacketConn 支持多播
	packetConn = ipv4.NewPacketConn(conn)
	packetConn.SetMulticastLoopback(true)

	// 加入多播组
	multicastAddr := &net.UDPAddr{IP: net.ParseIP(multicastGroup), Port: multicastPort}
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		if err := packetConn.JoinGroup(&iface, multicastAddr); err != nil {
			logWarn("Init", "Failed to join multicast on %s: %v", iface.Name, err)
		} else {
			logInfo("Init", "✓ Joined multicast on %s", iface.Name)
		}
	}

	// 启动 HTTP 服务器
	go startHTTPServer()

	// 启动 UDP 监听
	go listenMulticast()

	// 启动广播
	go startBroadcasting()

	// 清理离线设备
	go cleanupLoop()

	fmt.Println("\nCommands:")
	fmt.Println("  list              - List discovered devices")
	fmt.Println("  logs              - Show logs")
	fmt.Println("  clear             - Clear logs")
	fmt.Println("  quit              - Exit")
	fmt.Println()

	for !shouldStop {
		fmt.Print("> ")
		line, _ := reader.ReadString('\n')
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		switch line {
		case "list":
			listDevices()
		case "logs":
			printLogs()
		case "clear":
			clearLogs()
		case "quit", "exit":
			shouldStop = true
		default:
			fmt.Println("Unknown command")
		}
	}
}

func startHTTPServer() {
	mux := http.NewServeMux()
	mux.HandleFunc("/join", handleJoin)
	mux.HandleFunc("/info", handleInfo)

	addr := fmt.Sprintf(":%d", port)
	logInfo("HTTP", "HTTP server listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		if !shouldStop {
			logError("HTTP", "Server error: %v", err)
		}
	}
}

func handleJoin(w http.ResponseWriter, r *http.Request) {
	logDebug("HTTP", "← POST /join (from %s)", r.RemoteAddr)

	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}
	r.Body.Close()

	logDebug("HTTP", "  Body: %s", string(body))

	// 解析表单数据 deviceId=xxx&name=xxx&port=xxx
	values, err := url.ParseQuery(string(body))
	if err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	senderID := values.Get("deviceId")
	senderName := values.Get("name")
	senderPort := values.Get("port")

	if senderID == "" || senderID == deviceID {
		logDebug("HTTP", "  Ignoring self or invalid")
		w.Write([]byte("OK"))
		return
	}

	ip := r.RemoteAddr
	if idx := strings.LastIndex(ip, ":"); idx != -1 {
		ip = ip[:idx]
	}

	portNum := port
	fmt.Sscanf(senderPort, "%d", &portNum)

	deviceMu.Lock()
	devices[senderID] = &Device{
		Alias:    senderName,
		IP:       ip,
		Port:     portNum,
		ID:       senderID,
		LastSeen: time.Now(),
	}
	deviceMu.Unlock()

	logInfo("HTTP", "✓ Device joined: %s (%s:%d)", senderName, ip, portNum)

	w.Write([]byte("OK"))
}

func handleInfo(w http.ResponseWriter, r *http.Request) {
	logDebug("HTTP", "← GET /info (from %s)", r.RemoteAddr)

	info := fmt.Sprintf("deviceId=%s&name=%s&port=%d&type=%s",
		deviceID, deviceAlias, port, deviceType)
	w.Write([]byte(info))
}

func listenMulticast() {
	buf := make([]byte, 65536)
	logInfo("Multicast", "Listening on %s:%d", multicastGroup, multicastPort)

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
			logWarn("Multicast", "Read error: %v", err)
			continue
		}

		if !cm.Dst.IsMulticast() {
			continue
		}

		message := string(buf[:n])
		logDebug("Multicast", "★ UDP received: \"%s\" (from %s)", message, addr.String())

		// 解析 "deviceId,port" 格式
		parts := strings.Split(message, ",")
		if len(parts) < 2 {
			logWarn("Multicast", "  Invalid format: %s", message)
			continue
		}

		senderID := strings.TrimSpace(parts[0])
		senderPortStr := strings.TrimSpace(parts[1])

		if senderID == deviceID {
			logDebug("Multicast", "  Ignoring self")
			continue
		}

		var senderPort int
		fmt.Sscanf(senderPortStr, "%d", &senderPort)

		senderIP := addr.String()

		// 添加到设备列表
		deviceMu.Lock()
		devices[senderID] = &Device{
			Alias:    "Unknown",
			IP:       senderIP,
			Port:     senderPort,
			ID:       senderID,
			LastSeen: time.Now(),
		}
		deviceMu.Unlock()

		logInfo("Multicast", "✓ Discovered: %s (%s:%d)", senderID[:8]+"...", senderIP, senderPort)

		// 发送 HTTP join 请求
		go sendJoin(senderIP, senderPort)
	}
}

func sendJoin(targetIP string, targetPort int) {
	form := fmt.Sprintf("deviceId=%s&name=%s&port=%d", deviceID, deviceAlias, port)
	logDebug("HTTP", "→ POST /join to %s:%d", targetIP, targetPort)

	resp, err := http.Post(
		fmt.Sprintf("http://%s:%d/join", targetIP, targetPort),
		"application/x-www-form-urlencoded",
		strings.NewReader(form),
	)
	if err != nil {
		logWarn("HTTP", "✗ /join failed: %v", err)
		return
	}
	defer resp.Body.Close()

	logDebug("HTTP", "← /join response: %d", resp.StatusCode)
}

func startBroadcasting() {
	// 立即广播一次
	sendBroadcast()

	// 每 3 秒广播一次
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for !shouldStop {
		<-ticker.C
		sendBroadcast()
	}
}

func sendBroadcast() {
	message := fmt.Sprintf("%s,%d", deviceID, port)
	data := []byte(message)

	multicastAddr := &net.UDPAddr{IP: net.ParseIP(multicastGroup), Port: multicastPort}

	// 在每个接口上发送
	ifaces, _ := net.Interfaces()
	sent := 0
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}

		pc := ipv4.NewPacketConn(udpConn)
		if err := pc.SetMulticastInterface(&iface); err != nil {
			continue
		}

		n, err := pc.WriteTo(data, nil, multicastAddr)
		if err != nil {
			logWarn("Broadcast", "Failed on %s: %v", iface.Name, err)
		} else {
			sent++
			logDebug("Broadcast", "→ UDP: \"%s\" (%d bytes) via %s", message, n, iface.Name)
		}
	}

	if sent > 0 {
		logInfo("Broadcast", "✓ Broadcast sent on %d interfaces", sent)
	}
}

func cleanupLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for !shouldStop {
		<-ticker.C
		deviceMu.Lock()
		now := time.Now()
		for id, dev := range devices {
			if now.Sub(dev.LastSeen) > 15*time.Second {
				logInfo("Cleanup", "Device offline: %s", dev.Alias)
				delete(devices, id)
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
	for id, dev := range devices {
		age := time.Since(dev.LastSeen).Round(time.Second)
		fmt.Printf("  [%s] %s @ %s:%d (%s ago)\n", id[:8], dev.Alias, dev.IP, dev.Port, age)
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
