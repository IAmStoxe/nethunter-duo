// hid-type writes USB boot-keyboard reports to a configfs HID gadget.
package main

import (
	"fmt"
	"os"
	"strings"
	"time"
)

func send(modifier, usage byte) error {
	device := os.Getenv("DUO_HID_KEYBOARD")
	if device == "" {
		device = "/dev/hidg0"
	}
	f, err := os.OpenFile(device, os.O_WRONLY, 0)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err = f.Write([]byte{modifier, 0, usage, 0, 0, 0, 0, 0}); err != nil {
		return err
	}
	time.Sleep(8 * time.Millisecond)
	if _, err = f.Write(make([]byte, 8)); err != nil {
		return err
	}
	time.Sleep(8 * time.Millisecond)
	return nil
}

func key(c rune) (modifier, usage byte, ok bool) {
	if c >= 'a' && c <= 'z' {
		return 0, byte(c-'a') + 4, true
	}
	if c >= 'A' && c <= 'Z' {
		return 2, byte(c-'A') + 4, true
	}
	if c >= '1' && c <= '9' {
		return 0, byte(c-'1') + 30, true
	}
	if c == '0' {
		return 0, 39, true
	}
	switch c {
	case '\n':
		return 0, 40, true
	case '\t':
		return 0, 43, true
	case ' ':
		return 0, 44, true
	case '-':
		return 0, 45, true
	case '_':
		return 2, 45, true
	case '=':
		return 0, 46, true
	case '+':
		return 2, 46, true
	case '[':
		return 0, 47, true
	case '{':
		return 2, 47, true
	case ']':
		return 0, 48, true
	case '}':
		return 2, 48, true
	case '\\':
		return 0, 49, true
	case '|':
		return 2, 49, true
	case ';':
		return 0, 51, true
	case ':':
		return 2, 51, true
	case '\'':
		return 0, 52, true
	case '"':
		return 2, 52, true
	case '`':
		return 0, 53, true
	case '~':
		return 2, 53, true
	case ',':
		return 0, 54, true
	case '<':
		return 2, 54, true
	case '.':
		return 0, 55, true
	case '>':
		return 2, 55, true
	case '/':
		return 0, 56, true
	case '?':
		return 2, 56, true
	case '!':
		return 2, 30, true
	case '@':
		return 2, 31, true
	case '#':
		return 2, 32, true
	case '$':
		return 2, 33, true
	case '%':
		return 2, 34, true
	case '^':
		return 2, 35, true
	case '&':
		return 2, 36, true
	case '*':
		return 2, 37, true
	case '(':
		return 2, 38, true
	case ')':
		return 2, 39, true
	}
	return 0, 0, false
}

func namedKey(value string) (modifier, usage byte, err error) {
	parts := strings.Split(strings.ToUpper(strings.TrimSpace(value)), "+")
	keySeen := false
	for _, part := range parts {
		part = strings.TrimSpace(part)
		switch part {
		case "CTRL", "CONTROL":
			modifier |= 1
		case "SHIFT":
			modifier |= 2
		case "ALT":
			modifier |= 4
		case "GUI", "WIN", "WINDOWS", "META":
			modifier |= 8
		default:
			if keySeen || part == "" {
				return 0, 0, fmt.Errorf("invalid key combo: %s", value)
			}
			keySeen = true
			switch part {
			case "ENTER", "RETURN":
				usage = 40
			case "ESC", "ESCAPE":
				usage = 41
			case "BACKSPACE":
				usage = 42
			case "TAB":
				usage = 43
			case "SPACE":
				usage = 44
			case "CAPSLOCK":
				usage = 57
			case "PRINTSCREEN":
				usage = 70
			case "HOME":
				usage = 74
			case "PAGEUP", "PGUP":
				usage = 75
			case "DELETE", "DEL":
				usage = 76
			case "END":
				usage = 77
			case "PAGEDOWN", "PGDN":
				usage = 78
			case "RIGHT":
				usage = 79
			case "LEFT":
				usage = 80
			case "DOWN":
				usage = 81
			case "UP":
				usage = 82
			default:
				if len(part) == 2 && part[0] == 'F' && part[1] >= '1' && part[1] <= '9' {
					usage = 58 + part[1] - '1'
				} else if len(part) == 3 && part[0] == 'F' && part[1:] >= "10" && part[1:] <= "12" {
					usage = 67 + part[2] - '0'
				} else if len(part) == 1 && part[0] >= 'A' && part[0] <= 'Z' {
					usage = 4 + part[0] - 'A'
				} else if len(part) == 1 {
					var ok bool
					var implied byte
					implied, usage, ok = key(rune(part[0]))
					if !ok {
						return 0, 0, fmt.Errorf("unknown key: %s", part)
					}
					modifier |= implied
				} else {
					return 0, 0, fmt.Errorf("unknown key: %s", part)
				}
			}
		}
	}
	if !keySeen {
		return 0, 0, fmt.Errorf("combo has no key: %s", value)
	}
	return modifier, usage, nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: hid-type TEXT | hid-type --key CTRL+ALT+T")
		os.Exit(2)
	}
	if os.Args[1] == "--key" {
		if len(os.Args) != 3 {
			fmt.Fprintln(os.Stderr, "--key requires one combo")
			os.Exit(2)
		}
		modifier, usage, err := namedKey(os.Args[2])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		if err = send(modifier, usage); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	for _, c := range strings.Join(os.Args[1:], " ") {
		mod, usage, ok := key(c)
		if !ok {
			fmt.Fprintf(os.Stderr, "unsupported character: %q\n", c)
			os.Exit(2)
		}
		if err := send(mod, usage); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
}
