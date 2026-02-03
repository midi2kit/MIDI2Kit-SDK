# Contributing to MIDI2Kit

Thank you for your interest in contributing to MIDI2Kit! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and constructive in all interactions. We welcome contributors of all experience levels.

## Getting Started

### Prerequisites

- macOS 14.0+ (Sonoma or later)
- Xcode 16.0+
- Swift 6.0+
- iOS device with MIDI support (for hardware testing)

### Setting Up the Development Environment

1. Clone the repository:
   ```bash
   git clone https://github.com/hakaru/MIDI2Kit.git
   cd MIDI2Kit
   ```

2. Build the project:
   ```bash
   swift build
   ```

3. Run tests:
   ```bash
   swift test
   ```

## How to Contribute

### Reporting Issues

When reporting issues, please include:

- **Description**: Clear description of the problem
- **Steps to Reproduce**: Detailed steps to reproduce the issue
- **Expected Behavior**: What you expected to happen
- **Actual Behavior**: What actually happened
- **Environment**: macOS/iOS version, Xcode version, device model
- **MIDI Device**: If relevant, the MIDI device being used
- **Logs**: Any relevant log output (use `MIDI2Logger.isVerbose = true`)

### Submitting Pull Requests

1. **Fork** the repository
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** following the code style guidelines
4. **Add tests** for new functionality
5. **Run all tests** to ensure nothing is broken:
   ```bash
   swift test
   ```
6. **Commit** with a clear message:
   ```bash
   git commit -m "feat: Add new feature description"
   ```
7. **Push** and create a Pull Request

### Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `test:` Adding or updating tests
- `refactor:` Code refactoring
- `security:` Security improvements
- `chore:` Maintenance tasks

Examples:
```
feat: Add UMP to MIDI1 conversion
fix: Handle timeout in PE chunk assembly
docs: Update README with new examples
test: Add integration tests for CIManager
```

## Code Style Guidelines

### Swift Style

- **Swift 6.0+** with strict concurrency checking
- Use `actor` for thread-safe state management
- All public types must be `Sendable`
- Prefer `struct` over `class` for data types
- Use early returns to avoid deep nesting

### Naming Conventions

- **Types**: `UpperCamelCase` (e.g., `PEManager`, `DiscoveredDevice`)
- **Properties/Functions**: `lowerCamelCase` (e.g., `maxBufferSize`, `processData()`)
- **Constants**: `lowerCamelCase` (e.g., `defaultTimeout`)

### Documentation

- Add documentation comments for all public APIs
- Use Swift DocC format:
  ```swift
  /// Brief description of the function.
  ///
  /// Detailed description if needed.
  ///
  /// - Parameter name: Description of the parameter.
  /// - Returns: Description of the return value.
  /// - Throws: Description of errors that can be thrown.
  public func example(name: String) throws -> Result
  ```

### Error Handling

- Use meaningful error types (e.g., `PEError`, `CIError`)
- Never silently ignore errors
- Provide error classification (`isRetryable`, `isClientError`, etc.)

## Testing Requirements

### Unit Tests

- All new features must include unit tests
- Tests should cover both success and failure cases
- Use Swift Testing framework (`@Test`, `#expect`, `#require`)

### Integration Tests

- Add integration tests for cross-module functionality
- Use `MockMIDITransport` for hardware-independent testing

### Running Tests

```bash
# Run all tests
swift test

# Run specific test
swift test --filter TestClassName.testMethodName

# Run with verbose output
swift test --verbose
```

## Module Architecture

When contributing, understand the module hierarchy:

```
MIDI2Core (Foundation - no dependencies)
    ↑
    ├─ MIDI2Transport (CoreMIDI abstraction)
    ├─ MIDI2CI (Capability Inquiry)
    ├─ MIDI2PE (Property Exchange)
    └─ MIDI2Kit (High-Level API)
```

- **MIDI2Core**: Add fundamental types here
- **MIDI2Transport**: CoreMIDI-related changes
- **MIDI2CI**: Discovery and capability inquiry
- **MIDI2PE**: Property Exchange operations
- **MIDI2Kit**: High-level convenience APIs

## Device Compatibility

### Testing with Hardware

- Test with multiple MIDI devices when possible
- Document device-specific behaviors
- KORG devices have known quirks (see CLAUDE.md)

### Known Device Quirks

- **KORG Module Pro**: MIDI-CI 1.1 format, BLE MIDI packet loss
- Add workarounds with clear documentation

## Security Considerations

- Never log sensitive MIDI data in production
- Use `#if DEBUG` for debug-only logging
- Implement buffer size limits to prevent DoS
- Follow actor isolation for thread safety

## Getting Help

- Check existing [Issues](https://github.com/hakaru/MIDI2Kit/issues)
- Read the [CLAUDE.md](CLAUDE.md) for detailed technical documentation
- Review the [docs/](docs/) directory for additional resources

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to MIDI2Kit!
