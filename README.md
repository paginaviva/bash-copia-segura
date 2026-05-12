# bash-copia-segura

**Herramienta de copias de seguridad en Bash** con soporte para múltiples métodos de compresión (tar, zip, 7z, rsync) y subida a servidores externos mediante rclone.

![Tests](https://img.shields.io/badge/tests-61%2F61%20passed-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)
![Bash](https://img.shields.io/badge/language-Bash-4EAA25)

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
- **Parser seguro** de archivos .conf (sin `source` directo)
- **Validación de rutas** antes de operaciones destructivas

---

## Métodos disponibles

| Método | Formato | Compresión | Ideal para |
|---|---|---|---|
| `tar` | `.tar.gz` | gzip | Backup general, estándar Linux |
| `zip` | `.zip` | deflate | Compatibilidad con Windows, portabilidad |
| `7z` | `.7z` | LZMA2 | Máxima compresión, archivos grandes |
| `rsync` | — | incremental | Backups frecuentes, solo cambios |

---

## Estado del proyecto

| Indicador | Valor |
|-----------|-------|
| **Versión** | v1.0.0 |
| **Tests** | 61/61 passed |
| **Líneas de código** | ~530 (script) + ~470 (tests) |
| **Licencia** | MIT |

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

## Optimizaciones de seguridad incluidas

- **Parser seguro de .conf**: reemplaza `source` por lectura línea por línea con validación de formato `CLAVE=valor`
- **Guard en `rm -rf`**: valida que la ruta no esté vacía ni sea `/` antes de eliminar
- **Whitelist de flags rclone**: solo flags permitidos (`--verbose`, `--progress`, `--bwlimit`, etc.)
- **verify_backup bloqueante**: si la verificación de integridad falla, el script se detiene (no sube backups corruptos)
- **Caché de fecha**: reduce subprocesos calculando `date` una sola vez por ejecución

---

## Documentación

- [Guía de instalación](docs/INSTALACION.md)
- [Manual de uso](docs/MANUAL-USO.md)

---

## Licencia

MIT

---

## Créditos

Por **PáginaVIVA**

[Web](https://www.paginaviva.net/) · [GitHub](https://github.com/paginaviva)
