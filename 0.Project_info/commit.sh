#!/bin/bash

git add .

# Ejecutar git diff y guardar la salida en un archivo temporal
git diff HEAD -- . ':!:package-lock.json' > ./0.Project_info/cambios.tmp

# Reemplazar [[CHANGES]] en el archivo commit.md con el contenido del archivo temporal
sed -e "/\[\[CHANGES\]\]/{
  r ./0.Project_info/cambios.tmp
  d
}" ./0.Project_info/commit_en.md > ./0.Project_info/diff.md

# Eliminar el archivo temporal
rm ./0.Project_info/cambios.tmp

cat ./0.Project_info/diff.md | xclip -selection clipboard

rm ./0.Project_info/diff.md

# Imprimir un mensaje en la consola
echo "Cambios copiados al portapapeles."
