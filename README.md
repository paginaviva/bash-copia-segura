# bash-copia-segura

**Herramienta de copias de seguridad en Bash** con soporte para múltiples métodos de compresión (tar, zip, 7z, rsync) y subida a servidores externos mediante rclone.

---

## Características

- **4 métodos de backup** seleccionables por tarea: `tar`, `zip`, `7z`, `rsync`
- **Múltiples tareas** mediante archivos de configuración independientes (`.conf`)
- **Subida externa** a cualquier servicio (S3, SFTP, FTP, Google Drive, etc.) vía rclone
- **Verificación de integridad** automática según el método usado
- **Rotación** automática de backups antiguos (retención configurable en días)
- **Modo interactivo** (menú) y **no interactivo** (para cron)
- **Modo dry-run** para simular sin crear archivos
- **Logging** detallado con timestamp
- **Código 100% Bash**, sin dependencias externas más allá de las herramientas de sistema

---

## Métodos disponibles

| Método | Formato | Compresión | Ideal para |
|---|---|---|---|
| `tar` | `.tar.gz` | gzip | Backup general, estándar Linux |
| `zip` | `.zip` | deflate | Compatibilidad con Windows, portabilidad |
| `7z` | `.7z` | LZMA2 | Máxima compresión, archivos grandes |
| `rsync` | — | incremental | Backups frecuentes, solo cambios |

---

## Inicio rápido

```bash
# 1. Clonar
git clone https://github.com/tu-usuario/bash-copia-segura.git
cd bash-copia-segura

# 2. Crear una tarea de backup
cp configs/example.conf configs/mis-datos.conf
nano configs/mis-datos.conf
#   METHOD="zip"
#   SOURCE="/ruta/a/respaldar"
#   ARCHIVE_FOLDER="/ruta/destino"

# 3. Ejecutar
./copia-segura.sh

# 4. Probar sin crear archivos
./copia-segura.sh --dry-run --config mis-datos.conf

# 5. Ejecutar suite de pruebas
bash test.sh
```

---

## Documentación

- [Guía de instalación](docs/INSTALACION.md)
- [Manual de uso](docs/MANUAL-USO.md)

---

## Licencia

MIT
