# AI Agent Instructions

## Project Context

<!-- Replace with your project description -->

## Security Rules

- Never commit credentials, tokens, or secrets
- Validate all user input at system boundaries
- Use parameterized queries for database access
- Follow the principle of least privilege
- Flag any security concerns immediately

## Code Quality

- Follow the existing code style and conventions
- Write tests for new functionality
- Use conventional commit messages
- Keep PRs focused and under 400 lines when possible
- Run `pnpm lint` and `pnpm test` before committing

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for system architecture.

## Do Not

- Add dependencies without checking for CVEs and last commit date
- Refactor code that is not related to the current task
- Commit to main directly
- Skip tests or linting
