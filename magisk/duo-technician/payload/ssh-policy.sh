# Sourced by duo-kali. run executes the supplied command in the Kali chroot.
verify_ssh_policy() {
  effective=$(run 'install -d -m 0755 /run/sshd && ssh-keygen -A >/dev/null && /usr/sbin/sshd -t && /usr/sbin/sshd -T') || return 1
  for required in \
    '^permitrootlogin (without-password|prohibit-password)$' \
    '^authenticationmethods publickey$' \
    '^passwordauthentication no$' \
    '^kbdinteractiveauthentication no$' \
    '^pubkeyauthentication yes$' \
    '^usepam no$'; do
    printf '%s\n' "$effective" | grep -Eiq "$required" || return 1
  done
}
