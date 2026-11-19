# Surface Duo technician conveniences for interactive Kali shells.
alias ll='ls -alF --color=auto'
alias ports='ss -lntup'
alias routes='ip -c route'
alias links='ip -brief -c link'
alias disks='lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL'
alias usb='lsusb -tv'
alias candevs='ip -details -statistics link show type can'
alias journal-errors='journalctl -p warning..alert -b --no-pager'
alias shared='cd /mnt/shared'

servehere() {
  python3 -m http.server "${1:-8000}" --bind 0.0.0.0
}

extract() {
  [ -f "$1" ] || { echo "not a file: $1" >&2; return 1; }
  case "$1" in
    *.tar.bz2|*.tbz2) tar xjf "$1" ;;
    *.tar.gz|*.tgz) tar xzf "$1" ;;
    *.tar.xz|*.txz) tar xJf "$1" ;;
    *.zip) unzip "$1" ;;
    *.7z) 7z x "$1" ;;
    *.gz) gunzip "$1" ;;
    *.bz2) bunzip2 "$1" ;;
    *.xz) unxz "$1" ;;
    *) echo "unsupported archive: $1" >&2; return 2 ;;
  esac
}
