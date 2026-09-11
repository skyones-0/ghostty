# 👻 Ghostty (macOS Apple Silicon Edition)

[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon%20(ARM64)-black?logo=apple&style=flat-square)](https://github.com/skyones-0/ghostty)
[![Version](https://img.shields.io/badge/version-1.3.2-blue?style=flat-square)](https://github.com/skyones-0/ghostty/releases/tag/v1.3.2)
[![Renderer](https://img.shields.io/badge/renderer-Metal%20GPU-red?style=flat-square)](https://github.com/skyones-0/ghostty)
[![License](https://img.shields.io/badge/license-MPL%202.0-green?style=flat-square)](LICENSE)

Fast, native, GPU-accelerated terminal emulator engineered **exclusively for macOS Apple Silicon (M1/M2/M3/M4)**.

This distribution ([`skyones-0/ghostty`](https://github.com/skyones-0/ghostty)) brings specialized productivity enhancements tailored for modern developers, hardware hackers, and devops engineers on macOS.

---

## 🚀 Descargar y Probar

Ya puedes descargar la versión final compilada y optimizada lista para usar:

### [⬇️ **Descargar Ghostty v1.3.2 para macOS (Apple Silicon ARM64)**](https://github.com/skyones-0/ghostty/releases/download/v1.3.2/Ghostty-macos-arm64-v1.3.2.zip)

> **Instalación rápida en 1 paso:**
> 1. Descarga el archivo `.zip` y descomprímelo.
> 2. Mueve `Ghostty.app` a tu carpeta `/Applications`.
> 3. Abre tu terminal y ejecuta para habilitar la apertura sin restricciones de Gatekeeper:
> ```bash
> xattr -cr /Applications/Ghostty.app
> ```

---

## ✨ Características Exclusivas de Esta Versión

### 1. ⚡ Barra Lateral de Comandos Rápidos (*Quick Commands Sidebar*)
* **Atajo global**: `⌘ ⇧ B` o pulsando el **botón flotante** en la esquina inferior derecha.
* **Botón flotante minimalista**: Integrado en el visor del terminal (`SidebarToggleOverlay`) con material traslúcido y resplandor animado de neón al pasar el cursor.
* **Acciones en 1 click**:
  * Ejecutar directamente en el terminal activo (`▶`).
  * Pegar en la línea de comandos sin ejecutar para revisión (`✎`).
  * **Split & Send**: Abre automáticamente una división a la derecha y ejecuta el comando.
* **Modal de Parámetros Interactivo**: Si un comando contiene marcadores como `<host>`, `<rama>` o `<entorno>`, se despliega un diálogo emergente para rellenarlos antes de enviar.
* **Inyección Dinámica**: Soporte para variables automáticas como `{clipboard}` (contenido del portapapeles) y `{selection}` (texto seleccionado en el terminal).
* **Modo Transmisión (*Broadcast Mode*)**: Replica el envío del comando a **todas las divisiones de terminal abiertas** en la pestaña de forma simultánea.
* **Navegación por Teclado Completa**:
  * Flechas `↑` / `↓` para navegar cíclicamente.
  * `Return` para ejecutar, `⌥ Return` para insertar, `Escape` para devolver el foco al terminal.
* **Sincronización en Tiempo Real**: Guarda tus comandos en `~/.config/ghostty/quick-commands.json` y se actualiza al instante entre pestañas y ventanas mediante Darwin FSEvents.

---

### 2. 🔌 Detector de Dispositivos Serie USB (*Hardware Watcher*)
* **Detección instantánea vía IOKit**: Al conectar cualquier placa o dispositivo USB serie (ESP32, Arduino, Raspberry Pi Pico, módems, conversores FTDI/CH340/CP2102), Ghostty lo reconoce al segundo.
* **Toast Flotante Efímero**: Muestra una alerta flotante en la parte superior del terminal con el nombre del dispositivo, ruta (`/dev/cu.usbserial...`) y un selector de baudios (115200, 9600, etc.).
* **Conexión en 1 click**: Botón **Conectar** que abre una sesión de consola serie interactiva (`screen <puerto> <baud>`).

---

### 3. 🌐 Detector Automático de Servidores Locales (*Port Detector*)
* **Inspección de sockets en vivo**: Monitorea los procesos hijos en ejecución mediante llamadas al kernel Darwin `proc_pidinfo(PROC_PIDTASKINFO)`.
* **Detección inteligente de puertos**: Al arrancar servidores de desarrollo (Vite, Next.js, Django, FastAPI, Flask, Express, Docker, Go, etc.), detecta el puerto TCP abierto (`3000`, `5173`, `8000`, `8080`, `8787`...).
* **Banner flotante interactivo**: Muestra la URL local activa con un botón de **Abrir en Navegador** directo.

---

### 4. 🔔 Notificaciones de Comandos de Larga Duración
* **Alertas inteligentes de escritorio**: Si ejecutas un comando que toma más de 15 segundos (como `npm install`, `cargo build`, migraciones o backups) y cambias de aplicación o ventana, Ghostty te enviará una notificación nativa de macOS (`UNUserNotificationCenter`) cuando termine.
* **Toast interno de finalización**: Al volver al terminal, un toast flotante te confirmará el código de salida y el tiempo total de ejecución.

---

### 5. ☕ Mantener Despierto (*Keep Awake / Caffeinate*)
* **Control en la barra de menú**: Activa o desactiva la inhibición de suspensión del sistema de macOS directamente desde Ghostty para evitar que tu Mac se duerma durante scripts largos o descargas.

---

### 6. 📋 Copiar Salida del Último Comando (`⌘ ⇧ C`)
* **Extracción instantánea**: Copia el texto completo generado por la última orden ejecutada al portapapeles de macOS sin necesidad de seleccionarlo manualmente con el ratón. Incluye confirmación visual HUD.

---

### 7. ⚙️ Monitor de Procesos y Recursos en Vivo
* **Píldora de tareas activas**: Muestra un indicador en tiempo real en la cabecera (`[⠋ N bg]`) con el número de comandos en segundo plano.
* **Menú desplegable de control**: Lista de procesos con consumo de CPU Darwin y botón para finalizar tareas colgadas con `SIGTERM` en 1 click.

---

### 8. 🛠️ Config Studio Interactivo (`ghostty +config`)
* Interfaz interactiva desde terminal para configurar más de 60 opciones de Ghostty con vista previa de temas y paletas en vivo.

---

## 🛠️ Compilación desde el Código Fuente (macOS ARM64)

### Requisitos
- macOS 14 o superior (Apple Silicon M1/M2/M3/M4)
- **Xcode 26** con macOS SDK y Metal Toolchain
- **Zig 0.16.0** (`brew install zig`)

### Compilación Rápida Optimizada

```bash
# Compila en ReleaseFast con firma ad-hoc local lista para Sparkle
zig build -Doptimize=ReleaseFast -Demit-macos-app=true

# Instala la app en /Applications
rm -rf /Applications/Ghostty.app
cp -R macos/build/ReleaseLocal/Ghostty.app /Applications/Ghostty.app
xattr -cr /Applications/Ghostty.app
```

O usando el script automatizado:
```bash
./update-ghostty.sh --install
```

---

## 📄 Licencia

Ghostty está distribuido bajo la licencia Mozilla Public License 2.0. Consulta [LICENSE](LICENSE) para más detalles.
