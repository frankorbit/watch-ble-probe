set shell := ["bash", "-euc"]

generate:
    xcodegen generate

fix:
    swiftformat Shared Watch Mac Host iPhone iPhoneSetup Tests

check:
    swiftformat Shared Watch Mac Host iPhone iPhoneSetup Tests --lint
    swiftlint lint --strict

test:
    mkdir -p artifacts
    swiftc Watch/PointerInput.swift Tests/PointerInputTests.swift -o artifacts/pointer-input-tests
    artifacts/pointer-input-tests

build: generate
    xcodebuild -project WatchBLEProbe.xcodeproj -scheme WatchBLEProbe -destination 'generic/platform=watchOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
    xcodebuild -project WatchBLEProbe.xcodeproj -scheme MacBLEVerifier -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
    xcodebuild -project WatchBLEProbe.xcodeproj -scheme PhoneGATTHelper -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
    xcodebuild -project WatchBLEProbe.xcodeproj -scheme PhoneHIDSetup -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
