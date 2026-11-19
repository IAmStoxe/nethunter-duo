// injection-selftest transmits one harmless broadcast 802.11 probe request.
// It verifies monitor-mode frame injection without targeting another station.
package main

import (
	"fmt"
	"net"
	"os"
	"syscall"
)

const ethPAll = 0x0003

func htons(v uint16) uint16 { return v<<8 | v>>8 }

func main() {
	ifname := "wlan0"
	if len(os.Args) == 2 {
		ifname = os.Args[1]
	}
	iface, err := net.InterfaceByName(ifname)
	if err != nil {
		fmt.Fprintf(os.Stderr, "interface %s: %v\n", ifname, err)
		os.Exit(1)
	}

	proto := htons(ethPAll)
	fd, err := syscall.Socket(syscall.AF_PACKET, syscall.SOCK_RAW, int(proto))
	if err != nil {
		fmt.Fprintf(os.Stderr, "AF_PACKET socket: %v\n", err)
		os.Exit(1)
	}
	defer syscall.Close(fd)

	if err = syscall.SetsockoptString(fd, syscall.SOL_SOCKET, syscall.SO_BINDTODEVICE, ifname); err != nil {
		fmt.Fprintf(os.Stderr, "bind to %s: %v\n", ifname, err)
		os.Exit(1)
	}
	addr := &syscall.SockaddrLinklayer{Protocol: proto, Ifindex: iface.Index, Halen: 6}
	if err = syscall.Bind(fd, addr); err != nil {
		fmt.Fprintf(os.Stderr, "bind AF_PACKET: %v\n", err)
		os.Exit(1)
	}

	// Minimal radiotap header, broadcast probe request and wildcard SSID IE.
	frame := []byte{
		0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x40, 0x00, 0x00, 0x00,
		0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
		0x02, 0x00, 0x00, 0x00, 0x00, 0x01,
		0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
		0x00, 0x00,
		0x00, 0x00,
	}
	if err = syscall.Sendto(fd, frame, 0, addr); err != nil {
		fmt.Fprintf(os.Stderr, "send frame: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("injection self-test: sent %d bytes on %s (ifindex %d)\n", len(frame), ifname, iface.Index)
}
