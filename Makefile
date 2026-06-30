# Fast NONBlOCKING IO to stdout can
# cause Netlify builds to terminate unexpectantly. This forces stdout to block.
BLOCK_STDOUT_CMD           := python -c "import os,sys,fcntl; \
                                           flags = fcntl.fcntl(sys.stdout, fcntl.F_GETFL); \
                                           fcntl.fcntl(sys.stdout, fcntl.F_SETFL, flags&~os.O_NONBLOCK);"
HUGO_BIND_ADDRESS          ?= 127.0.0.1
KURED_GO_MOD_URL           ?= https://raw.githubusercontent.com/kubereboot/kured/$(VERSION)/go.mod

help:  ## Display this help menu.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
.PHONY: help

gen-content:
	./hack/gen-content.py

release: ## Update release docs and commit them. Usage: make release VERSION=1.23.0
	@test -n "$(VERSION)" || (echo "VERSION is required. Usage: make release VERSION=1.23.0" >&2; exit 1)
	@set -eu; \
	version="$(VERSION)"; \
	go_mod=$$(curl -fsSL "$(KURED_GO_MOD_URL)") || { echo "Could not fetch $(KURED_GO_MOD_URL)" >&2; exit 1; }; \
	kubectl=$$(printf '%s\n' "$$go_mod" | awk '$$1 == "k8s.io/kubectl" { sub(/^v/, "", $$2); print $$2 }'); \
	client_go=$$(printf '%s\n' "$$go_mod" | awk '$$1 == "k8s.io/client-go" { print $$2 }'); \
	apimachinery=$$(printf '%s\n' "$$go_mod" | awk '$$1 == "k8s.io/apimachinery" { print $$2 }'); \
	api_minor=$$(printf '%s\n' "$$apimachinery" | sed -E 's/^v[0-9]+\.([0-9]+)\..*/\1/'); \
	compat="1.$$((api_minor - 1)).x, 1.$${api_minor}.x, 1.$$((api_minor + 1)).x"; \
	test -n "$$kubectl" -a -n "$$client_go" -a -n "$$apimachinery" || { echo "Could not read k8s module versions from $(KURED_GO_MOD_URL)" >&2; exit 1; }; \
	grep -q "| $$version " content/en/docs/installation.md && { echo "content/en/docs/installation.md already has $$version" >&2; exit 1; }; \
	previous=$$(awk '/^# while writing latest is / { print $$6; exit }' content/en/docs/faq.md); \
	test -n "$$previous" || { echo "Could not find previous release in content/en/docs/faq.md" >&2; exit 1; }; \
	sed -i "s/$$previous/$$version/g" content/en/docs/faq.md; \
	row=$$(printf '| %-6s | %-17s | %-16s | %-19s | %-33s |' "$$version" "$$kubectl" "$$client_go" "$$apimachinery" "$$compat"); \
	awk -v row="$$row" 'BEGIN { inserted = 0 } /^\| ------ \|/ { print; print row; inserted = 1; next } { print } END { if (!inserted) exit 1 }' content/en/docs/installation.md > content/en/docs/installation.md.tmp; \
	mv content/en/docs/installation.md.tmp content/en/docs/installation.md; \
	git diff -- content/en/docs/faq.md content/en/docs/installation.md; \
	git commit -s -m "Update compat matrix for next release" -- content/en/docs/faq.md content/en/docs/installation.md
.PHONY: release

serve: gen-content ## Spawns a development server.
	hugo server \
		--bind ${HUGO_BIND_ADDRESS} \
		--buildDrafts \
		--buildFuture \
		--disableFastRender

production-build: gen-content ## Builds production build.
	hugo \
		--baseURL $(URL) \
		--gc \
		--minify \
		--enableGitInfo

preview-build: gen-content ## Builds a preview build (for e.g. a pull requests).
	hugo \
		--baseURL $(DEPLOY_PRIME_URL) \
		--buildFuture \
		--gc \
		--minify \
		--enableGitInfo

branch-build: gen-content ## Builds a Git branch (for e.g. development branches).
	hugo \
		--baseURL $(DEPLOY_PRIME_URL) \
		--buildDrafts \
		--buildFuture \
		--gc \
		--minify \
		--enableGitInfo
