# Guía de restauración — bash-copia-segura

> Este archivo y `bash-copia-segura.tar.gz` deben estar juntos en el mismo directorio.

---

## Índice

- [1. En el nuevo Codespace](#1-en-el-nuevo-codespace)
- [2. Verificar el proyecto](#2-verificar-el-proyecto)
- [3. Probar que funciona](#3-probar-que-funciona)
- [4. Hacer un backup real](#4-hacer-un-backup-real)
- [5. Continuar el desarrollo](#5-continuar-el-desarrollo)
- [6. Migrar a GitHub](#6-migrar-a-github)

---

## 1. En el nuevo Codespace

```bash
# 1. Descomprimir el package
tar -xzf bash-copia-segura.tar.gz
cd bash-copia-segura

# 2. Ver estructura
ls -la
```

---

## 2. Verificar el proyecto

```bash
# Ejecutar tests
bash test.sh
```

Deben salir **25/25 passed, 0 failed**.

Si faltan dependencias según tu sistema:

| Herramienta | Instalación (Debian/Ubuntu) |
|---|---|
| `zip` | `sudo apt install zip` |
| `p7zip-full` | `sudo apt install p7zip-full` |
| `rsync` | `sudo apt install rsync` |
| `rclone` | `sudo -v ; curl https://rclone.org/install.sh \| sudo bash` |

---

## 3. Probar que funciona

```bash
# Modo dry-run (simula sin crear archivos)
./copia-segura.sh --dry-run --config configs/example.conf

# Backup real con tar (responde "y" para confirmar)
echo "y" | ./copia-segura.sh --config configs/example.conf

# Backup real con zip
echo "y" | ./copia-segura.sh --config configs/desarrollo.conf
```

---

## 4. Hacer un backup real

Crea tu propia tarea:

```bash
cp configs/example.conf configs/mi-proyecto.conf
nano configs/mi-proyecto.conf
```

Edita las variables:

```bash
METHOD="zip"                              # tar | zip | 7z | rsync
SOURCE="/ruta/a/respaldar"
ARCHIVE_FOLDER="/ruta/destino/archivos"   # para tar/zip/7z
BACKUP_FOLDER="/ruta/destino/incremental" # solo para rsync
RETENTION_DAYS=7
REMOTE_ENABLED="false"                    # true si usas rclone
EXCLUDE_PATTERNS="*.tmp *.log node_modules"
```

Ejecutar:

```bash
./copia-segura.sh
```

---

## 5. Continuar el desarrollo

El archivo `AGENTS.md` contiene toda la información técnica para que otro agente (o tú mismo) pueda continuar:

- **Arquitectura** del script
- **Lo implementado** (5 fases completas)
- **Tests** y cómo ejecutarlos
- **Pendientes** y próximos pasos
- **Decisiones de diseño**

La carpeta `historial-investigacion/` contiene los 6 documentos de investigación previa (análisis de 25 repos de backup en GitHub, evaluaciones, planes aprobados).

---

## 6. Migrar a GitHub

Cuando estés listo para subirlo a un repo público:

```bash
# Desde la carpeta bash-copia-segura/
git init
git add .
git commit -m "Initial commit: bash-copia-segura v1.0"
git remote add origin https://github.com/TU-USUARIO/bash-copia-segura.git
git push -u origin main
```

---

*Documento generado el 2026-05-12.*
