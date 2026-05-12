# Sandbox App Documentation

## Architecture

This is a mock multi-language project used for testing CLI tool behavior.

### Components

- **Auth Service** (`src/auth.ts`): Handles user authentication and token management
- **Database Layer** (`src/database.ts`): Database abstraction with connection pooling
- **Config** (`src/config.py`): Application configuration management
- **Models** (`src/models.py`): Data models and business logic
- **Types** (`src/types.go`): Go type definitions

### Known Issues

See TODO and FIXME markers throughout the codebase. Common patterns:

- Missing input validation
- Hardcoded secrets
- No error handling in async functions
- Missing type hints in Python code
- Currency handling with float instead of Decimal

### Development Setup

```bash
npm install
pip install -r requirements.txt
go mod init sandbox-test-app
```
