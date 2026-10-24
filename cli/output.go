package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
)

type output struct {
	json   bool
	stdout io.Writer
	stderr io.Writer
	color  bool
}

const jsonContractVersion = 1

type jsonError struct {
	Code        string `json:"code"`
	Message     string `json:"message"`
	Fingerprint string `json:"fingerprint,omitempty"`
}

type jsonEnvelope struct {
	CLI   int        `json:"cli"`
	OK    bool       `json:"ok"`
	Data  any        `json:"data,omitempty"`
	Error *jsonError `json:"error,omitempty"`
}

func (o *output) writeEnvelope(envelope jsonEnvelope) {
	data, err := json.Marshal(envelope)
	if err != nil {
		data = []byte(`{"cli":1,"ok":false,"error":{"code":"encoding","message":"the result could not be encoded"}}`)
	}
	_, _ = o.stdout.Write(append(data, '\n'))
}

func (o *output) succeed(data any, human func()) int {
	if o.json {
		o.writeEnvelope(jsonEnvelope{CLI: jsonContractVersion, OK: true, Data: nullable(data)})
		return exitOK
	}
	if human != nil {
		human()
	}
	return exitOK
}

func (o *output) emit(data any, human func()) {
	if o.json {
		o.writeEnvelope(jsonEnvelope{CLI: jsonContractVersion, OK: true, Data: nullable(data)})
		return
	}
	if human != nil {
		human()
	}
}

func nullable(data any) any {
	if data == nil {
		return json.RawMessage("null")
	}
	return data
}

func (o *output) fail(err error) int {
	var cli *cliError
	if !errors.As(err, &cli) {
		cli = &cliError{exit: exitPeerError, code: "error", message: err.Error()}
	}
	if o.json {
		e := &jsonError{Code: cli.code, Message: cli.message}
		var fingerprint *fingerprintError
		if errors.As(err, &fingerprint) {
			e.Fingerprint = fingerprint.presented
		}
		o.writeEnvelope(jsonEnvelope{CLI: jsonContractVersion, OK: false, Error: e})
	} else {
		fmt.Fprintf(o.stderr, "clash-cli: %s\n", cli.message)
	}
	return cli.exit
}

func (o *output) printf(format string, args ...any) {
	fmt.Fprintf(o.stdout, format, args...)
}

func (o *output) bold(text string) string {
	if !o.color {
		return text
	}
	return "\x1b[1m" + text + "\x1b[0m"
}

func (o *output) dim(text string) string {
	if !o.color {
		return text
	}
	return "\x1b[2m" + text + "\x1b[0m"
}

func (o *output) table(header []string, rows [][]string) {
	widths := make([]int, len(header))
	for i, cell := range header {
		widths[i] = displayWidth(cell)
	}
	for _, row := range rows {
		for i := range header {
			if i < len(row) && displayWidth(row[i]) > widths[i] {
				widths[i] = displayWidth(row[i])
			}
		}
	}
	line := func(cells []string, style func(string) string) {
		var builder strings.Builder
		for i := range header {
			cell := ""
			if i < len(cells) {
				cell = cells[i]
			}
			if i == len(header)-1 {
				builder.WriteString(cell)
				break
			}
			builder.WriteString(cell)
			builder.WriteString(strings.Repeat(" ", widths[i]-displayWidth(cell)+2))
		}
		fmt.Fprintln(o.stdout, style(strings.TrimRight(builder.String(), " ")))
	}
	line(header, o.bold)
	for _, row := range rows {
		line(row, func(s string) string { return s })
	}
}

func displayWidth(text string) int {
	width := 0
	for _, r := range text {
		switch {
		case r >= 0x1100 && (r <= 0x115f || r == 0x2329 || r == 0x232a ||
			(r >= 0x2e80 && r <= 0xa4cf && r != 0x303f) || (r >= 0xac00 && r <= 0xd7a3) ||
			(r >= 0xf900 && r <= 0xfaff) || (r >= 0xfe30 && r <= 0xfe4f) || (r >= 0xff00 && r <= 0xff60) ||
			(r >= 0xffe0 && r <= 0xffe6) || (r >= 0x1f300 && r <= 0x1faff) || (r >= 0x20000 && r <= 0x3fffd)):
			width += 2
		case r == 0x200d || (r >= 0xfe00 && r <= 0xfe0f):
		default:
			width++
		}
	}
	return width
}

func formatBytes(value float64) string {
	units := []string{"B", "KB", "MB", "GB", "TB"}
	i := 0
	for value >= 1024 && i < len(units)-1 {
		value /= 1024
		i++
	}
	if i == 0 {
		return fmt.Sprintf("%.0f %s", value, units[i])
	}
	return fmt.Sprintf("%.1f %s", value, units[i])
}

func formatRate(bytesPerSecond float64) string {
	return formatBytes(bytesPerSecond) + "/s"
}
