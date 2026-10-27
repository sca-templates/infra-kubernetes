# Conventional Commits Generator

Generate a commit message following **strictly** the Conventional Commits conventions based on the provided changes.

## Mandatory Format

```
<type>[optional scope]: <description>

[optional body - detailed explanation]

[optional footer - breaking changes, closes issues]
```

## Valid Types (USE EXACTLY THESE)

- **feat**: New user functionality
- **fix**: Bug fix
- **perf**: Change that improves performance
- **build**: Changes in build system or external dependencies
- **ci**: Changes in CI/CD configuration
- **docs**: Documentation-only changes
- **refactor**: Code change that neither fixes a bug nor adds a feature
- **style**: Changes that don't affect code meaning (spaces, formatting, etc.)
- **test**: Add or correct tests
- **chore**: Other tasks that don't modify src or test files
- **revert**: Revert a previous commit

## Suggested Scopes (use if applicable)
`api`, `auth`, `ui`, `db`, `config`, `deps`, `security`, `performance`, `cli`, `utils`

## Mandatory Rules

1. **Title**: Maximum 72 characters, lowercase, no ending period
2. **Type**: Mandatory, lowercase
3. **Description**: Clear, concise, in english
4. **Body**: Optional, maximum 100 characters per line
5. **Footer**: For breaking changes use `BREAKING CHANGE:` or close issues with `Closes #123`

## Expected Output Examples

### Example 1 - New functionality:
```
feat(auth): agregar autenticación con JWT

- Implementar middleware de verificación de tokens
- Crear endpoint para login y registro
- Agregar validación de roles de usuario

Closes #45
```

### Example 2 - Bug fix:
```
fix(api): corregir error de validación en endpoint users

El endpoint /api/users no validaba correctamente el formato
del email, causando errores 500 en requests con emails inválidos.

Fixes #67
```

### Example 3 - Breaking change:
```
feat(api): cambiar estructura de respuesta de usuarios

BREAKING CHANGE: El campo 'name' ahora se llama 'fullName' 
en todas las respuestas de la API de usuarios.
```

## Instructions for the AI

1. **Carefully analyze** the provided changes
2. **Identify the main type** of change (only one type per commit)
3. **Choose the most specific scope** if relevant
4. **Write in clear technical english**
5. **Include context** in the body if changes are complex
6. **Mention breaking changes** if it changes public APIs
7. **Reference issues** if related

## Changes to Analyze

```
[[CHANGES]]
```

**Generate ONLY the commit message, without additional explanations.**
