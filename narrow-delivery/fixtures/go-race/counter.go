package counter

// Counter is incremented concurrently from many goroutines.
// BUG: the int is unguarded — `go test -race` detects a data race.
type Counter struct {
	n int
}

func (c *Counter) Inc() {
	c.n++
}

func (c *Counter) Value() int {
	return c.n
}
