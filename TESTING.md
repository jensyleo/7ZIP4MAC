# 7ZIP4MAC — Pending Manual Tests

Running log of what still needs a human to click through. Checked items were
confirmed OK by the owner; unchecked items are open.

## ✅ Confirmed OK by owner (2026-07-09, round 1)

- [x] Selección de fila (clic simple)
- [x] ⌘ + clic (multi-selección)
- [x] ⇧ + clic (rango)
- [x] Doble clic para entrar en carpeta (ver fix de fiabilidad abajo)
- [x] Doble clic sobre un archivo → Quick Look (ver fix de fiabilidad abajo)
- [x] Fila `..` para subir un nivel
- [x] Breadcrumb — se entiende y navega bien
- [x] Carpetas ocultas — ocultas por defecto, toggle en Preferencias funciona
- [x] Test de archivo seleccionado — funciona
- [x] Rendimiento general — mejoró con el cache del motor

## ✅ Confirmed OK — round 2 fixes (2026-07-09, used without issue in every
## session since)

- [x] Doble clic (entrar en carpetas, Quick Look) — cronómetro propio
      basado en `NSEvent.doubleClickInterval`, ya no falla.
- [x] Ordenar por Name — corregido para ordenar por nombre visible, no ruta.
- [x] Ordenar por Size — sigue funcionando tras el cambio.

## Pending — waiting on test files
- [ ] **Abrir formatos nuevos** — RAR, ISO, UDF, CAB, CPIO, XZ, Z, XAR,
      PKG/XIP, DMG, ARJ, LZH, WIM, RPM, DEB, CHM, NSIS, LZMA, AR, SquashFS,
      ext2/3/4, FAT, NTFS, HFS+, APFS, VHD/VHDX, VMDK, QCOW, VDI. Pendiente
      hasta que consigas archivos de ejemplo.
- [ ] **Cancelar extracción** — pendiente hasta conseguir un archivo grande.

## ✅ Confirmed OK by Claude (2026-07-10, motor real por terminal)
- [x] Instancia única — `open -n` dos veces → solo 1 proceso corriendo.
- [x] Recientes — abrir un archivo real deja su ruta en `recentArchives`.
- [x] Extract Selected con varios archivos — extrajo solo los seleccionados,
      dejando fuera el resto.
- [x] Split en volúmenes — el motor genera correctamente varios `.7z.00X`.
- [x] Password + Encrypt file names — sin contraseña no lista (headers
      cifrados), con la contraseña sí lista y marca `Encrypted = +`.
- [x] Benchmark — el motor corre y da resultados completos.

## Extracción
- [ ] Overwrite policy (no implementado en UI todavía — siempre sobrescribe).

## Comprimir (⌘N)
- [ ] Profile picker aplica ajustes automáticamente al elegir uno (UI —
      necesita clic).
- [ ] "Save these settings as a profile…" → aparece en Preferencias ▸ Profiles
      (UI — necesita clic).
- [ ] Diálogo final "Archive Created" → Open / Show in Finder / Done (UI).

## ✅ Confirmed OK by owner (2026-07-10, round 3 — probado a mano)
- [x] Drag & drop de salida — arrastrar un archivo a un lugar del Finder lo extrae solo ahí.
- [x] Menú contextual → Copy Name / Copy Path.
- [x] About / Help.
- [x] Comprimir: profile picker + "Save these settings as a profile…".
- [x] Inspector — contenido correcto para archivos y carpetas.
- [x] Quick Look — con el fix del bug de abajo.

### 🐛→✅ Bug encontrado durante esta ronda: Quick Look intermitente con el Inspector abierto
Reporte del usuario: "Seleccioné el archivo, activé el Inspector y después el Quick Look y
no me funcionó. Cambié a otras ventanas por un tiempo y al rato sí funcionó." Causa: los
campos de `InspectorView` usan `.textSelection(.enabled)` (los hace enfocables), y al abrir
el Inspector el foco de teclado podía movérseles — como Espacio/Return dependían del foco
(`.onKeyPress`), dejaban de disparar silenciosamente. Mismo patrón raíz que el bug de
Delete/Backspace (Ronda 9). Fix: los tres atajos (Espacio, Return, Delete/Backspace) ahora
usan un único monitor de `NSEvent`, independiente del foco.

## Cifrado
- [ ] Abrir un `.7z` cifrado → pide contraseña.
- [ ] Con el archivo ya abierto (contraseña ingresada), usar Add/Delete/Move/Copy
      → no debe volver a pedir la contraseña (se reutiliza en memoria mientras
      el archivo sigue abierto). Al cerrar y volver a abrir, sí debe pedirla de nuevo.

## Menú contextual
- [ ] Test / Test Selected desde el menú contextual (Copy Name/Path ya confirmado arriba).

## Preferencias (⌘,)
- [ ] Pestaña General: subcarpeta al extraer, revelar en Finder, mostrar ocultos.
- [ ] Pestaña Compression: formato/nivel/cifrado por defecto.
- [ ] Pestaña Profiles: ver los de fábrica + los guardados; borrar uno propio.

## ✅ Confirmed OK by Claude (2026-07-10, probado de verdad por terminal)
- [x] **Uninstall 7ZIP4MAC…** — ejecutado el flujo completo real (no solo
      revisión de código): reset de TCC, borrado de saved state/caches/
      HTTPStorages/preferencias, mover la app a la Papelera. Se encontró y
      corrigió un bug real (la asociación de archivos no volvía a Archive
      Utility si quedaba otra copia del bundle en el disco). Reinstalada
      la app al terminar — sigue funcionando normal.
