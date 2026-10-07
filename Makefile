# make test | run | app | release VERSION=x.y.z | icon | sample | clean
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
DEVELOPER_DIR := $(shell xcode-select -p)

# Con solo las Command Line Tools (sin Xcode), SwiftPM no encuentra Testing.framework por sí solo.
ifneq (,$(findstring CommandLineTools,$(DEVELOPER_DIR)))
TESTING := $(DEVELOPER_DIR)/Library/Developer
TEST_FLAGS := -Xswiftc -F -Xswiftc $(TESTING)/Frameworks -Xlinker -F -Xlinker $(TESTING)/Frameworks \
	-Xlinker -rpath -Xlinker $(TESTING)/Frameworks -Xlinker -rpath -Xlinker $(TESTING)/usr/lib
endif

.PHONY: build test run app release icon sample clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

# Compila en debug, reemplaza la instancia que esté corriendo y abre la app.
run:
	scripts/bundle.sh debug $(VERSION)
	-pkill -x CopyEzz && sleep 1
	open dist/CopyEzz.app

app:
	scripts/bundle.sh release $(VERSION)

release:
	@test -n "$(VERSION)" || { echo "Uso: make release VERSION=x.y.z"; exit 1; }
	scripts/release.sh $(VERSION)

icon:
	scripts/make-icon.sh

sample:
	scripts/make-sample.sh

clean:
	rm -rf .build dist
