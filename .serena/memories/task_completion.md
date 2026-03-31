# BitBinder Task Completion Checklist

## When Making Changes

### Before Editing Code
1. **Read copilot instructions** in `.github/copilot-instructions.md`
   - Treat user data as high-stakes
   - Never introduce silent delete/failure behavior
   - Always preserve existing user data
   - Audit persistence paths before changing

2. **Check data protection implications**
   - Will this change affect save/delete/sync/migration paths?
   - Is user data at risk of silent loss?
   - Are proper backups in place?

### During Development
1. **Follow architectural patterns**
   - Use Service layer for business logic
   - SwiftData models for data persistence
   - SwiftUI views for presentation
   - Proper error handling with logging

2. **Code quality checks**
   - Follow existing naming conventions
   - Add comprehensive error handling
   - Use DataOperationLogger for important operations
   - Include recovery mechanisms for failures

### After Making Changes

#### Required Validation Steps
1. **Build verification**
   ```bash
   xcodebuild -project thebitbinder.xcodeproj -scheme thebitbinder build
   ```

2. **Package dependency check**
   ```bash
   xcodebuild -resolvePackageDependencies -project thebitbinder.xcodeproj
   ```

3. **SwiftLint validation**  
   ```bash
   swiftlint
   ```

4. **Data protection audit**
   - Test save/load operations
   - Verify iCloud sync behavior
   - Check backup mechanisms
   - Validate no data loss scenarios

#### Testing Requirements
- **Manual testing**: Run on simulator and device
- **CloudKit testing**: Test with real iCloud account
- **Edge case testing**: Poor connectivity, storage full, etc.
- **Migration testing**: If models changed, test upgrade path

#### Documentation Updates
- Update code comments for complex logic
- Add to memory files if architectural changes
- Update README/docs if user-facing changes

## Deployment Checklist
1. **Version bump**: Update MARKETING_VERSION in project settings
2. **Archive build**: Create distribution archive
3. **TestFlight upload**: For internal testing
4. **App Store submission**: After thorough testing

## Emergency Procedures
- **Data corruption**: Use backup restoration procedures
- **CloudKit issues**: Fall back to local-only mode
- **Critical bugs**: Hot-fix deployment process
- **User data loss**: Recovery from emergency backups