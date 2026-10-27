# make test | run | app | release VERSION=x.y.z | icon | sample | clean
VERSION ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
DEVELOPER_DIR := $(shell xcode-select -p)

# Con solo las Command Line Tools (sin Xcode), SwiftPM no encuentra Testing.framework ni el plugin de
# sus macros por sí solo.
ifneq (,$(findstring CommandLineTools,$(DEVELOPER_DIR)))
TESTING := $(DEVELOPER_DIR)/Library/Developer
TEST_FLAGS := -Xswiftc -F -Xswiftc $(TESTING)/Frameworks -Xlinker -F -Xlinker $(TESTING)/Frameworks \
	-Xlinker -rpath -Xlinker $(TESTING)/Frameworks -Xlinker -rpath -Xlinker $(TESTING)/usr/lib \
	-Xswiftc -plugin-path -Xswiftc $(DEVELOPER_DIR)/usr/lib/swift/host/plugins/testing
# El SDK de macOS 27 convierte @State de SwiftUI en un macro cuyo plugin solo trae Xcode: se compila
# con el SDK 26 si está instalado (SDKROOT=… elige otro). Lo heredan scripts/bundle.sh y release.sh.
SDK26 := $(wildcard $(DEVELOPER_DIR)/SDKs/MacOSX26.sdk)
ifneq (,$(SDK26))
SDKROOT ?= $(SDK26)
export SDKROOT
endif
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
