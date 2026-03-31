# BitBinder Code Style & Patterns

## Naming Conventions
- **Classes/Structs**: PascalCase (`AudioRecordingService`, `JokeFolder`)
- **Properties/Methods**: camelCase (`isRecording`, `updateWordCount()`)  
- **Constants**: camelCase (`maxAudioSessionRetries`)
- **Files**: PascalCase matching main type (`Joke.swift`, `AudioRecordingService.swift`)

## Architecture Patterns

### Service Layer Pattern
- Services are singleton classes with `shared` instances
- Services handle specific domains (Audio, iCloud, Data Protection, etc.)
- Services use `@ObservableObject` for UI binding
- Example: `AudioRecordingService.shared`, `iCloudSyncService.shared`

### SwiftData Models
- Models are `@Model` classes that inherit from `NSObject` 
- Use SwiftData's `@Attribute` and `@Relationship` decorators
- Models include soft delete (`isDeleted`, `deletedDate`)
- Example: `Joke`, `JokeFolder`, `Recording`, `SetList`

### SwiftUI Views
- Views are `View` structs following SwiftUI patterns
- Use `@StateObject`, `@ObservedObject`, `@Environment` for data flow
- Modular components in separate files (`JokeComponents.swift`, `JokesViewModifiers.swift`)
- Navigation with programmatic routing

## Error Handling
- Comprehensive logging with `DataOperationLogger.shared`
- Graceful fallbacks (CloudKit → local storage → in-memory)
- User-facing error alerts for critical issues
- Print statements with emoji prefixes (`✅`, `⚠️`, `❌`, `🛡️`)

## Data Protection Philosophy
- **Never lose data**: Multiple backup strategies
- **Explicit operations**: No silent failures or deletions
- **Recovery mechanisms**: Always preserve user content
- **Audit trails**: Log all data operations

## Code Quality
- **SwiftLint**: Enforced linting rules
- **Function length**: Disabled for complex routers (`BitBuddyIntentRouter`)
- **Comments**: Extensive documentation for complex operations
- **Type safety**: Strong typing with proper optionals handling

## Memory Management
- Proper cleanup in `deinit` methods
- Memory warning observers for recording services
- Background task management for data operations