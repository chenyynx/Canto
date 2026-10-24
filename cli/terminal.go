package main

import (
	_ "embed"
	"os"

	"golang.org/x/sys/unix"
)

func isTerminal(file *os.File) bool {
	_, err := unix.IoctlGetTermios(int(file.Fd()), unix.TIOCGETA)
	return err == nil
}

// skillText is SKILL.md, printed by `clash-cli skill` for an agent to install.
//
//go:embed HELP.txt
var skillText string
