# Generador de Título y Descripción de Pull Request

Genera un **título y descripción de Merge/Pull Request** siguiendo **estrictamente** las convenciones de Conventional Commits basado en los cambios proporcionados.

## Formato Obligatorio

```

<type>[alcance opcional]: \<título>

[cuerpo opcional - explicación detallada de los cambios]

[pie de página opcional - cambios incompatibles, cierra issues]

```

## Tipos Válidos (USA EXACTAMENTE ESTOS)

- **feat**: Nueva funcionalidad de usuario
- **fix**: Corrección de errores
- **perf**: Cambio que mejora el rendimiento
- **build**: Cambios en el sistema de compilación o dependencias externas
- **ci**: Cambios en la configuración de CI/CD
- **docs**: Cambios solo de documentación
- **refactor**: Cambio de código que no corrige un error ni agrega una funcionalidad
- **style**: Cambios que no afectan el significado del código (espacios, formato, etc.)
- **test**: Añadir o corregir tests
- **chore**: Otras tareas que no modifican archivos src o test
- **revert**: Revertir un commit anterior

## Alcances Sugeridos (usar si aplica)

`api`, `auth`, `ui`, `db`, `config`, `deps`, `security`, `performance`, `cli`, `utils`

## Reglas Obligatorias

1. **Título**: Máximo 72 caracteres, minúsculas, sin punto final
2. **Tipo**: Obligatorio, minúsculas
3. **Título**: Claro, conciso, en inglés
4. **Cuerpo**: Opcional, máximo 100 caracteres por línea; incluir un resumen de todos los cambios clave
5. **Pie de página**: Para cambios incompatibles usar `BREAKING CHANGE:` o cerrar issues con `Closes #123`

## Instrucciones para la IA

1. **Analizar** los cambios proporcionados
2. **Determinar** el tipo principal del PR (solo un tipo)
3. **Seleccionar** el alcance más específico si es relevante
4. **Escribir** el título en inglés técnico claro
5. **Resumir** todos los cambios en el cuerpo, referenciando [[CHANGES]]
6. **Indicar** cambios incompatibles con `BREAKING CHANGE:` si aplica
7. **Referenciar** issues relacionados usando `Closes #` o `Fixes #`

## Cambios a Analizar

```

[[CHANGES]]

```

**Generar SOLO el título y la descripción del PR, sin explicaciones adicionales.**
