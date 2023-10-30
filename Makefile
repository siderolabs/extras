REGISTRY ?= ghcr.io
USERNAME ?= siderolabs
SHA ?= $(shell git describe --match=none --always --abbrev=8 --dirty)
TAG ?= $(shell git describe --tag --always --dirty)
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
REGISTRY_AND_USERNAME := $(REGISTRY)/$(USERNAME)
# inital commit time
# git rev-list --max-parents=0 HEAD
# git log d31b8c41c87600f2d881508bb40aad232659f9bb --pretty=%ct
SOURCE_DATE_EPOCH ?= "1602102660"

# Sync bldr image with Pkgfile
BLDR_IMAGE := ghcr.io/siderolabs/bldr:v0.2.2
BLDR ?= docker run --rm --volume $(PWD):/tools --entrypoint=/bldr \
	$(BLDR_IMAGE) graph --root=/tools

BUILD := docker buildx build
PLATFORM ?= linux/amd64,linux/arm64
PROGRESS ?= auto
PUSH ?= false
COMMON_ARGS := --file=Pkgfile
COMMON_ARGS += --provenance=false
COMMON_ARGS += --progress=$(PROGRESS)
COMMON_ARGS += --platform=$(PLATFORM)
COMMON_ARGS += --build-arg=SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH)

, := ,
empty :=
space = $(empty) $(empty)

TARGETS = install-cni talosctl-cni-bundle-install

all: $(TARGETS) ## Builds all known pkgs.

.PHONY: help
help: ## This help menu.
	@grep -E '^[a-zA-Z%_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

local-%: ## Builds the specified target defined in the Dockerfile using the local output type. The build result will be output to the specified local destination.
	@$(MAKE) target-$* TARGET_ARGS="--output=type=local,dest=$(DEST) $(TARGET_ARGS)"
	@PLATFORM=$(PLATFORM)

reproducibility-test:
	@$(MAKE) reproducibility-test-local-reproducibility

reproducibility-test-local-%: ## Builds the specified target defined in the Pkgfile using the local output type. The build result will be output to the specified local destination.
	@rm -rf _out1/ _out2/
	@$(MAKE) local-$* DEST=_out1
	@$(MAKE) local-$* DEST=_out2 TARGET_ARGS="--no-cache"
	@touch -ch -t $$(date -d @$(SOURCE_DATE_EPOCH) +%Y%m%d0000) _out1 _out2
	@diffoscope _out1 _out2
	@rm -rf _out1/ _out2/

target-%: ## Builds the specified target defined in the Dockerfile. The build result will only remain in the build cache.
	@$(BUILD) \
		--target=$* \
		$(COMMON_ARGS) \
		$(TARGET_ARGS) .

docker-%: ## Builds the specified target defined in the Dockerfile using the docker output type. The build result will be loaded into docker.
	@$(MAKE) target-$* TARGET_ARGS="$(TARGET_ARGS)"

.PHONY: $(TARGETS)
$(TARGETS):
	@$(MAKE) docker-$@ TARGET_ARGS="--tag=$(REGISTRY)/$(USERNAME)/$@:$(TAG) --push=$(PUSH)"

.PHONY: deps.png
deps.png:
	@$(BLDR) graph | dot -Tpng > deps.png
