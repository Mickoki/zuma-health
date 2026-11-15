package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"net/url"
	"strconv"
)

type errorDetail struct {
	Code    string            `json:"code"`
	Message string            `json:"message"`
	Fields  map[string]string `json:"fields,omitempty"`
}

func send(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(value)
}
func fail(w http.ResponseWriter, status int, code, message string, fields map[string]string) {
	send(w, status, struct {
		Error errorDetail `json:"error"`
	}{errorDetail{code, message, fields}})
}
func readJSON(w http.ResponseWriter, r *http.Request, target any) bool {
	return readJSONLimit(w, r, target, 256<<10)
}
func readJSONLimit(w http.ResponseWriter, r *http.Request, target any, limit int64) bool {
	media, _, e := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if e != nil || media != "application/json" {
		fail(w, 415, "unsupported_media_type", "Use application/json.", nil)
		return false
	}
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	err := dec.Decode(target)
	if err == nil {
		if e := dec.Decode(new(any)); e != io.EOF {
			if e == nil {
				err = errors.New("multiple values")
			} else {
				err = e
			}
		}
	}
	if err != nil {
		var large *http.MaxBytesError
		if errors.As(err, &large) {
			fail(w, 413, "body_too_large", "Request body exceeds endpoint limit.", nil)
		} else {
			fail(w, 400, "invalid_json", "Expected one JSON object with known fields and valid values.", nil)
		}
		return false
	}
	return true
}
func pagination(w http.ResponseWriter, r *http.Request) (int, int, bool) {
	q, err := url.ParseQuery(r.URL.RawQuery)
	if err != nil {
		fail(w, 400, "invalid_query", "Invalid query string.", nil)
		return 0, 0, false
	}
	values := map[string]int{"limit": 20, "offset": 0}
	for _, key := range []string{"limit", "offset"} {
		if a, ok := q[key]; ok {
			if len(a) != 1 {
				fail(w, 400, "invalid_query", "Pagination parameters must occur once.", nil)
				return 0, 0, false
			}
			n, e := strconv.Atoi(a[0])
			if e != nil || n < 0 || (key == "limit" && (n < 1 || n > 100)) {
				fail(w, 400, "invalid_query", "limit must be 1–100 and offset nonnegative.", nil)
				return 0, 0, false
			}
			values[key] = n
		}
	}
	return values["limit"], values["offset"], true
}
func list[T any](items []T, limit, offset, total int) any {
	return struct {
		Items  []T `json:"items"`
		Limit  int `json:"limit"`
		Offset int `json:"offset"`
		Total  int `json:"total"`
	}{items, limit, offset, total}
}
