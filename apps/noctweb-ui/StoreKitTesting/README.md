<a id="storekit-integration-tests"></a>

<h1 align="center">StoreKit integration tests</h1>

<p align="center"><strong>Exercise the support UI with Apple's local test products.</strong></p>

<p align="center">
  <a href="#overview">Overview</a> ·
  <a href="#getting-started">Getting started</a> ·
  <a href="#reference">Reference</a> ·
  <a href="#related-documentation">Related docs</a>
</p>

## Overview

The test target uses a signed macOS host and Apple's local StoreKit
configuration. It never charges a real account. Standalone SwiftPM tests
cannot access this local StoreKit service.

## Getting started

Install XcodeGen and use Xcode on macOS. From the **noctweave-net repository root**:

```sh
cd apps/noctweb-ui/StoreKitTesting
xcodegen generate
xcodebuild -project StoreKitTesting.xcodeproj -scheme StoreKitTesting \
  -destination 'platform=macOS' test
```

## Reference

Run the `StoreKitTesting` scheme in Xcode to inspect the optional support
card and tip sheet with local products. Keep the scheme's local StoreKit
configuration selected when exercising purchases.

## Related documentation

| Read | For |
| --- | --- |
| [Project overview](../../../README.md) | Native tools and repository setup |
| [Shared UI package](../Package.swift) | The package used by the test host |
| [Test host configuration](project.yml) | XcodeGen targets and scheme settings |
