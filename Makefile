VERSION ?= dev
LDFLAGS ?= -trimpath -ldflags="-X main.toolVersion=$(VERSION)"
BIN := versioner
DIST := dist

.PHONY: build test vet cross clean install fmt run

build:
	CGO_ENABLED=0 go build $(LDFLAGS) -o $(BIN) .

test:
	go test ./...

vet:
	go vet ./...

fmt:
	gofmt -w -l .

run: build
	./$(BIN)

install:
	CGO_ENABLED=0 go build $(LDFLAGS) -o $(BIN) .
	cp $(BIN) "$(GOPATH)/bin/versioner" 2>/dev/null || cp $(BIN) /usr/local/bin/versioner

cross:
	mkdir -p $(DIST)
	for target in \
		"darwin amd64 $(DIST)/$(BIN)-darwin-amd64" \
		"darwin arm64 $(DIST)/$(BIN)-darwin-arm64" \
		"linux amd64 $(DIST)/$(BIN)-linux-amd64" \
		"linux arm64 $(DIST)/$(BIN)-linux-arm64" \
		"windows amd64 $(DIST)/$(BIN)-windows-amd64.exe" \
	; do \
		set -- $$target; \
		echo "building $$1/$$2 -> $$3"; \
		CGO_ENABLED=0 GOOS=$$1 GOARCH=$$2 go build $(LDFLAGS) -o $$3 .; \
	done

clean:
	rm -rf $(DIST) $(BIN)
