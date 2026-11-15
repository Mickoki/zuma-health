package games

import "testing"

func TestFingerprintIncludesFactWording(t *testing.T) {
	value := 1.0
	r := Report{GameID: "fifteen", Metrics: Metrics{"moves": &value}}
	before := Fingerprint(r)
	original := labels["moves"]
	t.Cleanup(func() { labels["moves"] = original })
	labels["moves"] = "Updated move label"
	if Fingerprint(r) == before {
		t.Fatal("changed fact wording must invalidate the cached explanation")
	}
}
