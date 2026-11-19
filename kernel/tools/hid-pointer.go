// hid-pointer writes relative USB mouse reports to the second configfs HID gadget.
package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

func number(value string) int8 {
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < -127 || parsed > 127 {
		fmt.Fprintf(os.Stderr, "value must be -127..127: %s\n", value)
		os.Exit(2)
	}
	return int8(parsed)
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: hid-pointer move DX DY | click left|right|middle | scroll DELTA")
		os.Exit(2)
	}
	report := []byte{0, 0, 0, 0}
	switch strings.ToLower(os.Args[1]) {
	case "move":
		if len(os.Args) != 4 {
			fmt.Fprintln(os.Stderr, "move requires DX DY")
			os.Exit(2)
		}
		report[1], report[2] = byte(number(os.Args[2])), byte(number(os.Args[3]))
	case "click":
		if len(os.Args) != 3 {
			fmt.Fprintln(os.Stderr, "click requires left, right, or middle")
			os.Exit(2)
		}
		switch strings.ToLower(os.Args[2]) {
		case "left":
			report[0] = 1
		case "right":
			report[0] = 2
		case "middle":
			report[0] = 4
		default:
			fmt.Fprintln(os.Stderr, "unknown mouse button")
			os.Exit(2)
		}
	case "scroll":
		if len(os.Args) != 3 {
			fmt.Fprintln(os.Stderr, "scroll requires DELTA")
			os.Exit(2)
		}
		report[3] = byte(number(os.Args[2]))
	default:
		fmt.Fprintln(os.Stderr, "command must be move, click, or scroll")
		os.Exit(2)
	}

	device := os.Getenv("DUO_HID_POINTER")
	if device == "" {
		device = "/dev/hidg1"
	}
	f, err := os.OpenFile(device, os.O_WRONLY, 0)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer f.Close()
	if _, err = f.Write(report); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	time.Sleep(20 * time.Millisecond)
	if _, err = f.Write([]byte{0, 0, 0, 0}); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
