# Compilar Nexo Whisper desde fuente

Esta guía cubre el workflow local para compilar y empaquetar Nexo Whisper sin necesidad de cuenta Apple Developer (ad-hoc signing).

---

## Requisitos

- **macOS 14.4+** (Sequoia o más nuevo recomendado).
- **Xcode 16+** o **Xcode 26 beta** (necesario si tocás features que usan `ENABLE_NATIVE_SPEECH_ANALYZER`).
- **Command Line Tools** instaladas (`xcode-select --install`).
- **git** + **make**.
- Para empaquetar el `.dmg`: `brew install create-dmg`.

---

## Quick start

```bash
# 1. Clonar el repo (privado — necesitás invite)
git clone git@github.com:NexoStudioinc/nexo-whisper.git
cd nexo-whisper

# 2. (Solo primera vez) Apuntar xcodebuild a Xcode si está fuera de /Applications
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# O usar la env var DEVELOPER_DIR si Xcode vive en otro lado:
export DEVELOPER_DIR=/Volumes/Entorno\ Mac/Xcode/Xcode-beta.app/Contents/Developer

# 3. Build local
make local
```

El resultado queda en `~/Downloads/Nexo Whisper.app` con `LOCAL_BUILD` activado (es decir, en modo **Pro completo** automáticamente — útil para desarrollo).

---

## Detalle de `make local`

El target hace:

1. Verifica prerequisites (`git`, `xcodebuild`, `swift`).
2. Clona y compila `whisper.cpp` como XCFramework (solo la primera vez, en `~/VoiceInk-Dependencies/`).
3. Borra `.local-build/` (cache de DerivedData del repo).
4. `xcodebuild` con:
   - `-configuration Debug`
   - `-xcconfig LocalBuild.xcconfig` (ad-hoc signing, sin team)
   - `CODE_SIGN_ENTITLEMENTS=VoiceInk.local.entitlements` (sin iCloud / sin aps-environment, para no requerir cert Apple)
   - `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD'` (fuerza `licenseState = .licensed`)
5. Copia el `.app` a `~/Downloads/Nexo Whisper.app` con `xattr -cr` para limpiar atributos de cuarentena.

---

## Otros targets del Makefile

```bash
make check        # Verifica que git/xcodebuild/swift estén instalados
make whisper      # Clona y compila whisper.cpp si no existe
make setup        # whisper + apunta al framework
make build        # Build sin LOCAL_BUILD (igual al CI)
make run          # Abre Nexo Whisper.app si existe en ~/Downloads/ o DerivedData
make dev          # build + run
make clean        # Borra ~/VoiceInk-Dependencies (whisper.cpp incluido)
make help         # Lista todos los targets
```

---

## Empaquetar el DMG

```bash
# 1. Hacer make local primero (genera la .app en ~/Downloads/)
make local

# 2. Generar el fondo branded (PNG 600x400 con logo + flecha → Applications)
swift /tmp/generate_dmg_background.swift   # o adaptar el script propio

# 3. create-dmg
DIST="$HOME/Downloads/NexoWhisper-1.0.0.dmg"
rm -f "$DIST"
create-dmg \
  --volname "Nexo Whisper" \
  --volicon "$HOME/Downloads/Nexo Whisper.app/Contents/Resources/AppIcon.icns" \
  --background "/tmp/nexo_dmg_background.png" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Nexo Whisper.app" 175 190 \
  --hide-extension "Nexo Whisper.app" \
  --app-drop-link 425 190 \
  --no-internet-enable \
  "$DIST" \
  "$HOME/Downloads/Nexo Whisper.app"
```

El DMG resultante (~17 MB) tiene fondo branded, ícono custom del volumen y layout "drag to Applications".

---

## Firma de updates (Sparkle)

Cada release pública debe firmarse con la clave privada EdDSA guardada en el Keychain.

```bash
SIGN="$(pwd)/.local-build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
"$SIGN" "$HOME/Downloads/NexoWhisper-1.0.0.dmg"
```

El output es el `sshSignature` que va al `appcast.xml` enclosure.

> ⚠️ **No perder la clave privada**. Backup con `generate_keys -x ~/backup.txt` y guardar fuera del repo (1Password, iCloud Keychain, disco cifrado).

---

## Troubleshooting

### `xcode-select: error: tool 'xcodebuild' requires Xcode`
Tenés Command Line Tools pero no Xcode completo apuntado.

```bash
# Si Xcode vive en /Applications:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Si vive en otro lado (ej. disco externo):
export DEVELOPER_DIR="/ruta/a/Xcode.app/Contents/Developer"
```

### `BUILD FAILED` con errores en `ENABLE_NATIVE_SPEECH_ANALYZER`
Necesitás **Xcode 26 beta** con SDK macOS 26. Si tenés Xcode estable, comentá el flag en `project.pbxproj` (4 ocurrencias: Debug + Release × 2 configs).

### `make local` reporta exit 0 pero la app no aparece
Bash pipefail: `make | tail` siempre da exit 0 aunque make falle. Validá siempre con:

```bash
make local > /tmp/build.log 2>&1
echo "Exit: $?"
grep -E "error:" /tmp/build.log
```

### TCC permisos se resetean a cada build
Solucionado en la versión actual: el Makefile NO re-codesigna entre builds, así los permisos TCC (Mic, Accesibilidad, Input Monitoring) sobreviven.

---

## Estructura del repo

```
.
├── VoiceInk/                    Código Swift de la app
│   ├── Models/                  CustomPrompt, LicenseViewModel, TranscriptionModel...
│   ├── Services/                LemonSqueezyService, FeatureGate, AIService...
│   ├── Views/                   SwiftUI views
│   ├── Transcription/           Whisper + Parakeet + Cloud providers + Streaming
│   ├── Paste/                   ClipboardManager + CursorPaster
│   ├── PowerMode/               App Profiles (Pro feature)
│   ├── Notifications/           AnnouncementManager + AppNotifications
│   ├── Shortcuts/               Hotkey + middle-click handling
│   ├── Resources/               Localizable.xcstrings (ES/EN)
│   ├── Info.plist               + entitlements (full y local)
├── VoiceInk.xcodeproj/          Project + scheme
├── VoiceInkTests/               Tests vacíos (placeholders del template Xcode)
├── VoiceInkUITests/             UI tests vacíos
├── LocalBuild.xcconfig          Ad-hoc signing config
├── Makefile                     Sistema de build
├── appcast.xml                  Sparkle feed (a hostear)
├── announcements.json           In-app announcements (servicio desactivado por ahora)
└── README.md / BUILDING.md / CONTRIBUTING.md / LICENSE
```

---

Cualquier duda: [soporte@nexostudio.xyz](mailto:soporte@nexostudio.xyz)
