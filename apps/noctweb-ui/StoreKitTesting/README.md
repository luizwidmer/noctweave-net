# StoreKit integration tests

The tests use a signed macOS host and Apple’s local StoreKit configuration. They never charge a real account. Standalone SwiftPM tests cannot access the local StoreKit service.

```sh
xcodegen generate
xcodebuild -project StoreKitTesting.xcodeproj -scheme StoreKitTesting -destination 'platform=macOS' test
```

Run the scheme in Xcode to inspect the optional support card and tip sheet with local products.
