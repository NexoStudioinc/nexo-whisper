# Nexo Whisper

App de macOS para dictar texto en cualquier lugar de tu Mac con transcripción 100% local. **Dictá. Soltá. Listo.**

Fork privado de [VoiceInk](https://github.com/Beingpax/VoiceInk) (GPL v3) — ver sección de [Licencia](#licencia) más abajo.

---

## ¿Qué hace?

Apretás un hotkey, hablás, soltás. La transcripción se pega donde tengas el cursor (Slack, Cursor, Notion, Gmail, lo que sea). Sin enviar audio a la nube, sin esperar internet.

**Plus**:
- Mejora opcional con IA (BYOK o cloud con licencia Pro).
- Modos por App: cambia automáticamente prompt y modelo según la app activa.
- Diccionario propio + sugerencias automáticas de palabras raras.
- Historial completo de tus dictados.

---

## Free vs Pro

### 🆓 Free (gratis para siempre, sin trial)

- Transcripción local con **Whisper** (Base, Small, Medium, Large v3 Turbo, Quantized) + **Parakeet** V2/V3 (NVIDIA).
- **Mejora con IA usando tu propia API key** (BYOK): Anthropic, OpenAI, Gemini, Groq.
- **Diccionario** + reemplazos de palabras + vocabulario.
- **Atajos globales** personalizables (push-to-talk o toggle).
- **Historial** completo: ver, re-transcribir, re-mejorar, exportar CSV.
- **1 prompt predefinido** (System Default — limpieza mínima preservando contenido).

### 💰 Pro ($7.99 USD, una vez, 1 Mac por licencia)

Todo lo de Free, más:

- **Transcripción cloud**: Groq, Deepgram, ElevenLabs, AssemblyAI, Soniox, Speechmatics, Mistral.
- **Modos por App** (Power Mode): auto-configurar prompt + modelo por aplicación o sitio web.
- **Transcribir Audio**: procesar archivos .mp3, .wav, .m4a, .mp4, .mov, etc.
- **Mejora vía CLI local**: Claude Code, Codex, Antigravity, Copilot, Pi.
- **7 prompts predefinidos extras**: Chat, Email, Rewrite, Formal, Coding, Summary, Fun.
- **Prompts custom ilimitados** con triggers por voz.
- **Soporte prioritario** y actualizaciones gratis de por vida.

Comprar en [store.nexowhisper.com](https://store.nexowhisper.com). Procesado por Lemon Squeezy con reembolsos a 30 días.

---

## Instalación

1. Descargá la última release desde [GitHub Releases](https://github.com/NexoStudioinc/nexo-whisper-releases/releases) (próximamente).
2. Abrí el `.dmg` y arrastrá **Nexo Whisper** a la carpeta `Applications`.
3. **Primera apertura**: click derecho sobre la app → "Abrir" → confirmar el warning de Gatekeeper. *(Notarización Apple en proceso — después del primer Open, doble click funciona normal.)*
4. La app te va a pedir permisos: Micrófono, Accesibilidad, Input Monitoring, y opcionalmente Screen Recording.
5. Asigná un hotkey en Settings (por default: tecla Fn).

Requiere **macOS 14.4+** en Apple Silicon (M1, M2, M3, M4) o Intel.

---

## Stack técnico

- **Swift 6 + SwiftUI** (UI nativa).
- **SwiftData** (historial y diccionario, con sync iCloud opcional).
- **whisper.cpp** vía XCFramework (transcripción local).
- **FluidAudio** (modelos Parakeet).
- **Sparkle** (auto-updates con firma EdDSA).
- **Lemon Squeezy** License API (gestión de licencias).

---

## Compilar local

Ver [BUILDING.md](BUILDING.md) para el workflow completo (`make local`).

---

## Licencia

**GPL v3** — heredada del fork upstream de [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk).

- El binario que vendemos como Pro es GPL — los compradores reciben acceso al código fuente vía repo privado de GitHub.
- Si querés ver el código sin comprar, el upstream original está [acá](https://github.com/Beingpax/VoiceInk).

**Atribución**:
- Código base original: **Prakash Joshi** ([Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk)).
- Fork rebrandeado + features adicionales: **Nexo Studio**.

---

## Soporte

- 📧 [soporte@nexostudio.xyz](mailto:soporte@nexostudio.xyz)
- 📖 [docs.nexowhisper.com](https://docs.nexowhisper.com)
- 🌐 [nexowhisper.com](https://nexowhisper.com)

---

Desarrollado por **[Nexo Studio](https://nexostudio.xyz)** · Hecho en Argentina 🇦🇷
