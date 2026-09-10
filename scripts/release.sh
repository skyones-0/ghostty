#!/usr/bin/env bash
set -euo pipefail

# scripts/release.sh
# Automates the release process for Ghostty:
# 1. Validates version tag argument
# 2. Builds Ghostty in Release mode (zig build -Doptimize=ReleaseFast)
# 3. Archives macos/build/Release/Ghostty.app into Ghostty.zip
# 4. Signs Ghostty.zip with Sparkle's sign_update using Ed25519 key from Keychain
# 5. Updates appcast.xml with the new release entry
# 6. Commits appcast.xml and tags the commit
# 7. Creates a GitHub Release using gh release create and uploads Ghostty.zip
# 8. Pushes git commits and tags to origin main

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ -z "${1:-}" ]; then
  echo "Uso: $0 <version>"
  echo "Ejemplo: $0 1.1.0"
  exit 1
fi

RAW_VERSION="$1"
VERSION="${RAW_VERSION#v}"
TAG="v$VERSION"
ZIP_NAME="Ghostty.zip"
APPCAST_FILE="$REPO_ROOT/appcast.xml"

# Find Sparkle sign_update tool
SIGN_UPDATE_BIN="$(find /Users/jaraujo/Library/Developer/Xcode/DerivedData -name "sign_update" -perm +111 2>/dev/null | head -n 1 || true)"
if [ -z "$SIGN_UPDATE_BIN" ] || [ ! -x "$SIGN_UPDATE_BIN" ]; then
  echo "Error: No se encontró la herramienta sign_update de Sparkle."
  exit 1
fi

echo "========================================="
echo " Lanzando Release $TAG para skyones-0/ghostty"
echo "========================================="

# 1. Compilar en modo ReleaseFast
echo "==> 1. Compilando Ghostty (ReleaseFast)..."
zig build -Doptimize=ReleaseFast --summary all

RELEASE_APP="$REPO_ROOT/macos/build/Release/Ghostty.app"
if [ ! -d "$RELEASE_APP" ]; then
  echo "Error: No se encontró $RELEASE_APP tras la compilación."
  exit 1
fi

# 2. Comprimir la aplicación preservando atributos y firmas macOS
echo "==> 2. Comprimiendo $ZIP_NAME..."
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "$RELEASE_APP" "$ZIP_NAME"

# 3. Firmar el archivo zip con Sparkle
echo "==> 3. Firmando $ZIP_NAME con Sparkle Ed25519..."
SIGN_OUTPUT=$("$SIGN_UPDATE_BIN" "$ZIP_NAME")
echo "Firma obtenida: $SIGN_OUTPUT"

# Extraer edSignature y length del output
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
FILE_SIZE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')

if [ -z "$ED_SIGNATURE" ] || [ -z "$FILE_SIZE" ]; then
  echo "Error al extraer la firma de sign_update."
  exit 1
fi

# 4. Actualizar appcast.xml
echo "==> 4. Actualizando $APPCAST_FILE..."
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
BUILD_NUMBER=$(date "+%Y%m%d%H%M")
DOWNLOAD_URL="https://github.com/skyones-0/ghostty/releases/download/$TAG/$ZIP_NAME"

python3 - << EOF
import xml.etree.ElementTree as ET

tree = ET.parse("$APPCAST_FILE")
root = tree.getroot()
channel = root.find("channel")

namespaces = {
    "sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle",
    "dc": "http://purl.org/dc/elements/1.1/"
}
for prefix, uri in namespaces.items():
    ET.register_namespace(prefix, uri)

# Eliminar items existentes con la misma versión si ya existieran
for item in channel.findall("item"):
    ver = item.find("sparkle:shortVersionString", namespaces)
    if ver is not None and ver.text == "$VERSION":
        channel.remove(item)

# Crear nuevo item
item = ET.Element("item")

title = ET.SubElement(item, "title")
title.text = "Ghostty $TAG"

pubDate = ET.SubElement(item, "pubDate")
pubDate.text = "$PUB_DATE"

sparkle_version = ET.SubElement(item, "sparkle:version")
sparkle_version.text = "$BUILD_NUMBER"

sparkle_short = ET.SubElement(item, "sparkle:shortVersionString")
sparkle_short.text = "$VERSION"

sparkle_min = ET.SubElement(item, "sparkle:minimumSystemVersion")
sparkle_min.text = "13.0.0"

enclosure = ET.SubElement(item, "enclosure")
enclosure.set("url", "$DOWNLOAD_URL")
enclosure.set("sparkle:edSignature", "$ED_SIGNATURE")
enclosure.set("length", "$FILE_SIZE")
enclosure.set("type", "application/octet-stream")

# Insertar al inicio de la lista de items
first_item_index = None
for i, child in enumerate(list(channel)):
    if child.tag == "item":
        first_item_index = i
        break

if first_item_index is not None:
    channel.insert(first_item_index, item)
else:
    channel.append(item)

ET.indent(tree, space="  ", level=0)
tree.write("$APPCAST_FILE", encoding="utf-8", xml_declaration=True)
EOF

echo "==> appcast.xml actualizado con éxito para $TAG."

# 5. Commit y Tag
echo "==> 5. Creando commit y tag para $TAG..."
git add "$APPCAST_FILE"
git commit -S -m "release: $TAG" || true
git tag -s "$TAG" -m "Ghostty $TAG" || true

# 6. Publicar Release en GitHub
echo "==> 6. Publicando Release en GitHub..."
if command -v gh >/dev/null 2>&1; then
  gh release create "$TAG" "$ZIP_NAME" --title "Ghostty $TAG" --notes "Ghostty $TAG"
  echo "==> 7. Haciendo push de cambios y tags a origin..."
  git push origin main --tags
  echo "========================================="
  echo " ¡Release $TAG publicado exitosamente en GitHub!"
  echo " Los usuarios recibirán la actualización automáticamente."
  echo "========================================="
else
  echo "gh CLI no disponible. Sube $ZIP_NAME manualmente al release $TAG en GitHub y haz: git push origin main --tags"
fi
