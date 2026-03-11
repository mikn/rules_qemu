package vm

import (
	"fmt"
	"os/exec"
	"runtime"
	"strings"
)

// validateTapDevice checks that a tap device exists.
// On non-Linux systems this is a no-op since TAP networking is Linux-only.
func validateTapDevice(name string) error {
	if runtime.GOOS != "linux" {
		return nil
	}
	cmd := exec.Command("ip", "link", "show", name)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("tap device %q not found: %s", name, strings.TrimSpace(string(output)))
	}
	return nil
}

// validateBridge checks that a bridge exists and is administratively UP.
// On non-Linux systems this is a no-op since bridge networking is Linux-only.
//
// Note: We check for the UP flag (inside <...> in `ip link show` output),
// not "state UP". A bridge with no active TAP devices shows "state DOWN"
// (no carrier) but still has the UP flag set — that's the expected state
// before QEMU attaches to the TAP devices.
func validateBridge(name string) error {
	if runtime.GOOS != "linux" {
		return nil
	}
	cmd := exec.Command("ip", "link", "show", name)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("bridge %q not found", name)
	}
	outputStr := string(output)
	// Parse the flags between < and > — e.g. "<NO-CARRIER,BROADCAST,MULTICAST,UP>"
	// The UP flag means administratively enabled, which is what we need.
	start := strings.Index(outputStr, "<")
	end := strings.Index(outputStr, ">")
	if start == -1 || end == -1 || end <= start {
		return fmt.Errorf("bridge %q: could not parse interface flags from: %s", name, strings.TrimSpace(outputStr))
	}
	flags := outputStr[start+1 : end]
	for _, flag := range strings.Split(flags, ",") {
		if flag == "UP" {
			return nil
		}
	}
	return fmt.Errorf("bridge %q exists but is not UP (flags: %s)", name, flags)
}
