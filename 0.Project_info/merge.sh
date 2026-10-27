#!/bin/bash

# Obtener el nombre de la rama actual
current_branch=$(git rev-parse --abbrev-ref HEAD)

git add .

# Ejecutar git diff usando el tag anterior en lugar de HEAD
git diff origin/main HEAD -- . ':!:package-lock.json' > ./0.Project_info/cambios.tmp

# Reemplazar [[CHANGES]] en el archivo commit.md con el contenido del archivo temporal
sed -e "/\[\[CHANGES\]\]/{
  r ./0.Project_info/cambios.tmp
  d
}" ./0.Project_info/pr_en.md > ./0.Project_info/diff.md

# Eliminar el archivo temporal
rm ./0.Project_info/cambios.tmp

cat ./0.Project_info/diff.md | xclip -selection clipboard

rm ./0.Project_info/diff.md

# Imprimir un mensaje en la consola
echo "Cambios copiados al portapapeles."

# Actualizar con main y hacer push de la rama actual
git pull origin main --no-edit && git push origin "$current_branch"
