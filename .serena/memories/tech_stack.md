# BitBinder Tech Stack & Dependencies

## Platform & Language
- **Platform**: iOS 17.0+, macOS 14.0+ (Mac Catalyst), iPadOS 17.0+
- **Language**: Swift 5.0
- **Framework**: SwiftUI 
- **Data**: SwiftData with CloudKit sync
- **Architecture**: MVVM with Service layer

## Swift Package Dependencies
1. **swift-algorithms** (v1.2.1+) - Apple's algorithms library
2. **generative-ai-swift** (v0.5.0+) - Google's Generative AI SDK 
3. **OpenAI** (v0.4.7+) - MacPaw's OpenAI SDK for GPT integration

### Transitive Dependencies
- **swift-numerics** (v1.1.1) - Apple's numerics library
- **swift-openapi-runtime** (v1.11.0) - OpenAPI runtime support
- **swift-http-types** (v1.5.1) - HTTP type definitions

## Development Tools
- **Xcode**: Primary IDE
- **SwiftLint**: Code linting and style enforcement  
- **ExtensionKit**: For app extensions (bit.appex)

## Data Architecture
- **Primary Store**: SwiftData with `default.store`
- **Cloud Sync**: CloudKit private database (`iCloud.The-BitBinder.thebitbinder`)
- **Backup Strategy**: Multi-layered with emergency backups
- **Key-Value Store**: iCloud KV store for preferences

## Build Targets
- **Main App**: `thebitbinder` - Full SwiftUI app
- **Extension**: `bit` - ExtensionKit extension for quick access

## Deployment Targets
- iOS: 17.0+  
- macOS: 14.0+ (Catalyst)
- Swift: 5.0

## Known Issues
- ⚠️ Extension deployment target inconsistency (26.2 vs 17.0)
- Uses Mac Catalyst for macOS support