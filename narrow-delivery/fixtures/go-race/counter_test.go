package counter

import (
	"sync"
	"testing"
)

// Run with: go test -race
func TestConcurrentInc(t *testing.T) {
	c := &Counter{}
	var wg sync.WaitGroup
	const goroutines, perG = 50, 1000
	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < perG; j++ {
				c.Inc()
			}
		}()
	}
	wg.Wait()
	if got := c.Value(); got != goroutines*perG {
		t.Fatalf("Value() = %d, want %d", got, goroutines*perG)
	}
}
