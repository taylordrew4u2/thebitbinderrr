# BitBinder Development Commands

## Building & Running

### Xcode Commands
```bash
# Build the project
xcodebuild -project thebitbinder.xcodeproj -scheme thebitbinder -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

# Build for all platforms  
xcodebuild -project thebitbinder.xcodeproj -scheme thebitbinder -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -destination 'platform=macOS' build

# Clean build
xcodebuild -project thebitbinder.xcodeproj clean

# Resolve package dependencies
xcodebuild -resolvePackageDependencies -project thebitbinder.xcodeproj

# Archive for distribution
xcodebuild -project thebitbinder.xcodeproj -scheme thebitbinder archive
```

### Simulator & Device
```bash
# List available simulators
xcrun simctl list devices

# Run on iPhone simulator
open -a Simulator --args -CurrentDeviceUDID [DEVICE_ID]

# Install on device (after build)
xcrun devicectl device install app --device [DEVICE_ID] [APP_PATH]
```

## Package Management
```bash
# Resolve dependencies (when packages are missing)
xcodebuild -resolvePackageDependencies -project thebitbinder.xcodeproj

# Update packages to latest versions
# (Use Xcode Package Manager UI: File → Package Dependencies → Update to Latest Package Versions)
```

## Code Quality

### SwiftLint
```bash
# Install SwiftLint (if not already installed)
brew install swiftlint

# Lint the codebase
swiftlint

# Lint with auto-fix
swiftlint --fix

# Lint specific files
swiftlint lint --path thebitbinder/Models/
```

## Testing
- ⚠️ No automated tests currently configured
- Manual testing through Xcode simulator and device testing
- CloudKit testing requires actual iCloud account

## Debugging Commands
```bash
# Clean derived data (fixes many build issues)
rm -rf ~/Library/Developer/Xcode/DerivedData

# Clear Swift package cache
rm -rf ~/Library/Caches/org.swift.swiftpm

# Reset simulator
xcrun simctl erase all

# View device logs
xcrun devicectl device log stream --device [DEVICE_ID]
```

## macOS Development (Darwin-specific)
- Uses `bash` as default shell
- Standard macOS file operations (`ls`, `cd`, `grep`, `find`)
- Xcode Command Line Tools required
- Homebrew recommended for additional tools