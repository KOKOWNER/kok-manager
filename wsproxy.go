// wsproxy.go - KOK Websockets Proxy (falconproxy-compatible role)
// A small WebSocket -> SSH proxy written for KOK SSH Manager.
// Accepts WebSocket upgrade requests on one or more TCP ports and pipes
// the stream to a local backend (default 127.0.0.1:22). Non-WebSocket
// requests get a plain camouflage HTTP response (profile dependent).
//
// Usage: falconproxy -ports "80 8080" -backend 127.0.0.1:22 -profile rustfast|vodafone|v0
package main

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"time"
)

var (
	portsFlag   = flag.String("ports", "8080", "space-separated listen ports")
	backendFlag = flag.String("backend", "127.0.0.1:22", "backend TCP address")
	profileFlag = flag.String("profile", "rustfast", "profile: rustfast | vodafone | v0")
)

const wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

func acceptKey(key string) string {
	h := sha1.New()
	io.WriteString(h, key+wsGUID)
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

// readFrame reads one WebSocket frame, returns payload and opcode.
func readFrame(r *bufio.Reader) ([]byte, byte, error) {
	b0, err := r.ReadByte()
	if err != nil {
		return nil, 0, err
	}
	b1, err := r.ReadByte()
	if err != nil {
		return nil, 0, err
	}
	op := b0 & 0x0f
	masked := b1&0x80 != 0
	length := uint64(b1 & 0x7f)
	if length == 126 {
		var ext [2]byte
		if _, err := io.ReadFull(r, ext[:]); err != nil {
			return nil, 0, err
		}
		length = uint64(binary.BigEndian.Uint16(ext[:]))
	} else if length == 127 {
		var ext [8]byte
		if _, err := io.ReadFull(r, ext[:]); err != nil {
			return nil, 0, err
		}
		length = binary.BigEndian.Uint64(ext[:])
	}
	var mask [4]byte
	if masked {
		if _, err := io.ReadFull(r, mask[:]); err != nil {
			return nil, 0, err
		}
	}
	payload := make([]byte, length)
	if _, err := io.ReadFull(r, payload); err != nil {
		return nil, 0, err
	}
	if masked {
		for i := range payload {
			payload[i] ^= mask[i%4]
		}
	}
	return payload, op, nil
}

// writeFrame writes one unmasked server->client frame.
func writeFrame(w io.Writer, opcode byte, payload []byte) error {
	var hdr []byte
	hdr = append(hdr, 0x80|opcode)
	switch n := len(payload); {
	case n < 126:
		hdr = append(hdr, byte(n))
	case n <= 65535:
		hdr = append(hdr, 126, byte(n>>8), byte(n))
	default:
		hdr = append(hdr, 127)
		var ext [8]byte
		binary.BigEndian.PutUint64(ext[:], uint64(n))
		hdr = append(hdr, ext[:]...)
	}
	if _, err := w.Write(hdr); err != nil {
		return err
	}
	_, err := w.Write(payload)
	return err
}

func landing(profile string) string {
	switch profile {
	case "vodafone":
		return "HTTP/1.1 200 OK\r\nServer: Apache\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n<html><head><title>Welcome</title></head><body><h1>It works!</h1></body></html>"
	case "v0":
		return ""
	default: // rustfast
		return "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nOK"
	}
}

func handleConn(client net.Conn, profile string) {
	defer client.Close()
	br := bufio.NewReader(client)
	// Read HTTP request line + headers.
	var headers []string
	for {
		line, err := br.ReadString('\n')
		if err != nil {
			return
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break
		}
		headers = append(headers, line)
		if len(headers) > 64 {
			return
		}
	}
	joined := strings.ToLower(strings.Join(headers, "\n"))
	var wsKey string
	for _, h := range headers {
		if strings.HasPrefix(strings.ToLower(h), "sec-websocket-key:") {
			wsKey = strings.TrimSpace(h[len("sec-websocket-key:"):])
		}
	}
	if !strings.Contains(joined, "upgrade: websocket") || wsKey == "" {
		if resp := landing(profile); resp != "" {
			io.WriteString(client, resp)
		}
		return
	}
	resp := "HTTP/1.1 101 Switching Protocols\r\n" +
		"Upgrade: websocket\r\n" +
		"Connection: Upgrade\r\n" +
		"Sec-WebSocket-Accept: " + acceptKey(wsKey) + "\r\n\r\n"
	if _, err := io.WriteString(client, resp); err != nil {
		return
	}
	backend, err := net.DialTimeout("tcp", *backendFlag, 5*time.Second)
	if err != nil {
		return
	}
	defer backend.Close()

	var once sync.Once
	closeBoth := func() { client.Close(); backend.Close() }

	// client (WS frames) -> backend (raw)
	go func() {
		defer once.Do(closeBoth)
		for {
			payload, op, err := readFrame(br)
			if err != nil {
				return
			}
			switch op {
			case 0x8: // close
				return
			case 0x9: // ping -> pong
				_ = writeFrame(client, 0xA, payload)
			case 0x1, 0x2, 0x0: // text/binary/continuation -> forward
				if _, err := backend.Write(payload); err != nil {
					return
				}
			}
		}
	}()

	// backend (raw) -> client (WS binary frames)
	buf := make([]byte, 32768)
	for {
		n, err := backend.Read(buf)
		if n > 0 {
			if werr := writeFrame(client, 0x2, buf[:n]); werr != nil {
				break
			}
		}
		if err != nil {
			break
		}
	}
	once.Do(closeBoth)
}

func main() {
	flag.Parse()
	profile := strings.ToLower(*profileFlag)
	ports := strings.Fields(*portsFlag)
	if len(ports) == 0 {
		fmt.Println("no ports given")
		return
	}
	var wg sync.WaitGroup
	for _, p := range ports {
		ln, err := net.Listen("tcp", ":"+p)
		if err != nil {
			fmt.Printf("listen :%s failed: %v\n", p, err)
			continue
		}
		fmt.Printf("falconproxy (%s) listening on :%s -> %s\n", profile, p, *backendFlag)
		wg.Add(1)
		go func(ln net.Listener) {
			defer wg.Done()
			for {
				c, err := ln.Accept()
				if err != nil {
					return
				}
				go handleConn(c, profile)
			}
		}(ln)
	}
	wg.Wait()
}
