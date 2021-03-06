REPO=blacktop
NAME=ipsw
CUR_VERSION=$(shell svu current)
NEXT_VERSION=$(shell svu patch)


.PHONY: build-deps
build-deps: ## Install the build dependencies
	@echo " > Installing build deps"
	brew install go goreleaser

.PHONY: dev-deps
dev-deps: ## Install the dev dependencies
	@echo " > Installing dev deps"
	go get -u github.com/spf13/cobra/cobra
	go get -u golang.org/x/tools/cmd/cover
	go get -u github.com/caarlos0/svu

.PHONY: setup
setup: build-deps dev-deps ## Install all the build and dev dependencies

.PHONY: dry_release
dry_release: ## Run goreleaser without releasing/pushing artifacts to github
	@echo " > Creating Pre-release Build ${NEXT_VERSION}"
	@goreleaser build --rm-dist --skip-validate

.PHONY: release
release: ## Create a new release from the NEXT_VERSION
	@echo " > Creating Release ${NEXT_VERSION}"
	@hack/make/release ${NEXT_VERSION}
	@goreleaser --rm-dist

.PHONY: release-minor
release-minor: ## Create a new minor semver release
	@echo " > Creating Release $(shell svu minor)"
	@hack/make/release $(shell svu minor)
	@goreleaser --rm-dist

.PHONY: destroy
destroy: ## Remove release from the CUR_VERSION
	@echo " > Deleting Release ${CUR_VERSION}"
	rm -rf dist
	git tag -d ${CUR_VERSION}
	git push origin :refs/tags/${CUR_VERSION}

build: ## Build ipsw
	@echo " > Building ipsw"
	@go mod download
	@CGO_ENABLED=0 go build ./cmd/ipsw

.PHONY: docs
docs: ## Build the hugo docs
	@echo " > Building Docs"
	hack/publish/gh-pages

.PHONY: test-docs
test-docs: ## Start local server hosting hugo docs
	@echo " > Testing Docs"
	cd docs; hugo server -D

.PHONY: update_mod
update_mod: ## Update go.mod file
	@echo " > Updating go.mod"
	rm go.sum
	go mod download
	go mod tidy

.PHONY: update_devs
update_devs: ## Parse XCode database for new devices
	@echo " > Updating device_traits.json"
	CGO_ENABLED=1 CGO_CFLAGS=-I/usr/local/include CGO_LDFLAGS=-L/usr/local/lib CC=gcc go run ./cmd/ipsw/main.go device-list-gen pkg/xcode/device_traits.json

.PHONY: update_keys
update_keys: ## Scrape the iPhoneWiki for AES keys
	@echo " > Updating firmware_keys.json"
	CGO_ENABLED=0 go run ./cmd/ipsw/main.go key-list-gen pkg/info/data/firmware_keys.json

.PHONY: docker
docker: ## Build docker image
	@echo " > Building Docker Image"
	docker build -t $(REPO)/$(NAME):$(NEXT_VERSION) .

.PHONY: docker-tag
docker-tag: docker ## Tag docker image
	docker tag $(REPO)/$(NAME):$(NEXT_VERSION) docker.pkg.github.com/blacktop/ipsw/$(NAME):$(NEXT_VERSION)

.PHONY: docker-ssh
docker-ssh: ## SSH into docker image
	@docker run --init -it --rm --device /dev/fuse --cap-add SYS_ADMIN --mount type=tmpfs,destination=/app -v `pwd`/test-caches/ipsws:/data --entrypoint=bash $(REPO)/$(NAME):$(NEXT_VERSION)

.PHONY: docker-push
docker-push: docker-tag ## Push docker image to github
	docker push docker.pkg.github.com/blacktop/ipsw/$(NAME):$(NEXT_VERSION)

.PHONY: docker-test
docker-test: ## Run docker test
	@echo " > Testing Docker Image"
	docker run --init -it --rm --device /dev/fuse --cap-add=SYS_ADMIN -v `pwd`:/data $(REPO)/$(NAME):$(NEXT_VERSION) -V extract --dyld /data/iPhone12_1_13.2.3_17B111_Restore.ipsw

clean: ## Clean up artifacts
	@echo " > Cleaning"
	rm *.tar || true
	rm *.ipsw || true
	rm kernelcache.release.* || true
	rm -rf dist

# Absolutely awesome: http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help