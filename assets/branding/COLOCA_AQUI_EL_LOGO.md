# Imágenes de marca de El Alazán

Hay dos archivos con propósitos distintos:

### 1. `logo.png` — el logo DENTRO de la app
Lo muestra la barra superior y el menú lateral (widget `BrandLogo`).
Mientras no exista, se dibuja un monograma dorado de respaldo.
- PNG, idealmente cuadrado, fondo incluido o transparente.

### 2. `icon.png` — el ICONO del ejecutable (.exe / .apk / ventana)
Lo usa `flutter_launcher_icons` para generar el icono de Windows,
Android y macOS. Ya hay uno provisional con la identidad de la marca.

**Para poner el logo real del caballo como icono:**
1. Guarda tu logo cuadrado (≥512 px) como `assets/branding/icon.png`
   (puedes reemplazar el provisional).
2. Ejecuta:
   ```bash
   dart run flutter_launcher_icons
   ```
3. Vuelve a compilar (`flutter build windows --release`).

Tip: si tu logo no es cuadrado, déjalo sobre un lienzo cuadrado verde
para que no se recorte en el icono.
