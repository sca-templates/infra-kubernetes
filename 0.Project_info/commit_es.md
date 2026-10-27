# Generador de Commits Convencionales

Genera un mensaje de commit siguiendo **estrictamente** las convenciones de Conventional Commits basado en los cambios proporcionados.

## Formato Obligatorio

```
<tipo>[alcance opcional]: <descripción>

[cuerpo opcional - explicación detallada]

[footer opcional - breaking changes, closes issues]
```

## Tipos Válidos (USAR EXACTAMENTE ESTOS)

- **feat**: Nueva funcionalidad para el usuario
- **fix**: Corrección de un bug
- **perf**: Cambio que mejora el rendimiento
- **build**: Cambios en sistema de build o dependencias externas
- **ci**: Cambios en configuración de CI/CD
- **docs**: Sólo cambios en documentación
- **refactor**: Cambio de código que no corrige bug ni agrega funcionalidad
- **style**: Cambios que no afectan el significado del código (espacios, formato, etc.)
- **test**: Agregar o corregir tests
- **chore**: Otras tareas que no modifican src o test files
- **revert**: Revierte un commit previo

## Alcances Sugeridos (usar si aplica)
`api`, `auth`, `ui`, `db`, `config`, `deps`, `security`, `performance`, `cli`, `utils`

## Reglas Obligatorias

1. **Título**: Máximo 72 caracteres, minúsculas, sin punto final
2. **Tipo**: Obligatorio, en minúsculas
3. **Descripción**: Clara, concisa, en español
4. **Cuerpo**: Opcional, máximo 100 caracteres por línea
5. **Footer**: Para breaking changes usar `BREAKING CHANGE:` o cerrar issues con `Closes #123`

## Ejemplos de Output Esperado

### Ejemplo 1 - Funcionalidad nueva:
```
feat(auth): agregar autenticación con JWT

- Implementar middleware de verificación de tokens
- Crear endpoint para login y registro
- Agregar validación de roles de usuario

Closes #45
```

### Ejemplo 2 - Corrección de bug:
```
fix(api): corregir error de validación en endpoint users

El endpoint /api/users no validaba correctamente el formato
del email, causando errores 500 en requests con emails inválidos.

Fixes #67
```

### Ejemplo 3 - Breaking change:
```
feat(api): cambiar estructura de respuesta de usuarios

BREAKING CHANGE: El campo 'name' ahora se llama 'fullName' 
en todas las respuestas de la API de usuarios.
```

## Instrucciones para la IA

1. **Analiza cuidadosamente** los cambios proporcionados
2. **Identifica el tipo principal** de cambio (un sólo tipo por commit)
3. **Escoge el alcance** más específico si es relevante
4. **Redacta en español** claro y técnico
5. **Incluye contexto** en el cuerpo si los cambios son complejos
6. **Menciona breaking changes** si cambia APIs públicas
7. **Referencia issues** si están relacionados

## Cambios a Analizar

```
[[CHANGES]]
```

**Genera SÓLO el mensaje de commit, sin explicaciones adicionales.**
