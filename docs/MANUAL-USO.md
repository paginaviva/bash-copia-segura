# Manual de uso — bash-copia-segura

## Índice

- [1. Estructura de archivos](#1-estructura-de-archivos)
- [2. Archivos de configuración (.conf)](#2-archivos-de-configuración-conf)
- [3. Modos de ejecución](#3-modos-de-ejecución)
- [4. Métodos de backup](#4-métodos-de-backup)
- [5. Subida externa con rclone](#5-subida-externa-con-rclone)
- [6. Exclusión de archivos](#6-exclusión-de-archivos)
- [7. Rotación de backups](#7-rotación-de-backups)
- [8. Programar con cron](#8-programar-con-cron)
- [9. Ejemplos prácticos](#9-ejemplos-prácticos)

---

## 1. Estructura de archivos

```
bash-copia-segura/
├── copia-segura.sh        # Script principal
├── configs/               # Carpeta de configuraciones
│   ├── example.conf       # Plantilla con todas las variables
│   └── desarrollo-en-curso.conf    # Ejemplo para workspace de desarrollo
├── logs/                  # Logs de ejecución (se crea automáticamente)
│   └── backup_YYYY-MM-DD.log
├── test.sh                # Suite de pruebas
├── README.md              # Documentación principal
├── docs/
│   ├── INSTALACION.md     # Guía de instalación
│   └── MANUAL-USO.md      # Este manual
└── LICENSE                # MIT
```

---

## 2. Archivos de configuración (.conf)

Cada tarea de backup es un archivo `.conf` dentro de `configs/`. Puedes tener tantos como necesites.

### Variables disponibles

| Variable | Obligatorio | Valores | Descripción |
|---|---|---|---|
| `METHOD` | Sí | `tar`, `zip`, `7z`, `rsync` | Método de backup |
| `SOURCE` | Sí* | Ruta absoluta | Directorio a respaldar |
| `BACKUP_FOLDER` | Para rsync | Ruta absoluta | Destino del rsync incremental |
| `ARCHIVE_FOLDER` | Para tar/zip/7z | Ruta absoluta | Destino de los archivos comprimidos |
| `RETENTION_DAYS` | No (default 7) | Número | Días a conservar backups |
| `REMOTE_ENABLED` | No | `true`, `false` | Activar subida externa |
| `REMOTE_DEST` | Si REMOTE_ENABLED | `remoto:ruta` | Destino rclone |
| `REMOTE_OPTS` | No | Flags | Opciones extra para rclone |
| `EXCLUDE_PATTERNS` | No | Patrones separados por espacio | Archivos/carpetas a excluir |

*\*SOURCE puede omitirse si se usa solo rsync sin archive, pero no es recomendable.*

### Ejemplo mínimo (tar)

```bash
METHOD="tar"
SOURCE="/home/usuario/documentos"
ARCHIVE_FOLDER="/mnt/disco/backups"
```

### Ejemplo con rsync + archive comprimido

```bash
METHOD="rsync"
SOURCE="/var/www/html"
BACKUP_FOLDER="/mnt/backups/rsync-html"
ARCHIVE_FOLDER="/mnt/backups/archives-html"
RETENTION_DAYS=14
```

En este modo, `rsync` hace la copia incremental y luego se genera un `.tar.gz` del resultado.

### Ejemplo con subida externa

```bash
METHOD="zip"
SOURCE="/home/usuario/fotos"
ARCHIVE_FOLDER="/mnt/backups/fotos"
REMOTE_ENABLED="true"
REMOTE_DEST="misdrive:Backups/fotos"
REMOTE_OPTS="--verbose"
RETENTION_DAYS=30
```

---

## 3. Modos de ejecución

### Modo interactivo (por defecto)

```bash
./copia-segura.sh
```

Si hay un solo `.conf`:

```
Only one configuration found. Using: desarrollo-en-curso.conf
```

Si hay varios:

```
Available backup configurations:
  [0] desarrollo-en-curso.conf
  [1] servidor-web.conf
  [2] fotos.conf
Select a configuration to run (number):
```

### Modo no interactivo (para cron)

```bash
./copia-segura.sh --config desarrollo-en-curso.conf
```

### Modo simulación (dry-run)

```bash
./copia-segura.sh --dry-run --config desarrollo-en-curso.conf
```

Muestra lo que se haría sin crear ningún archivo.

### Listar configuraciones

```bash
./copia-segura.sh --list
```

### Ayuda

```bash
./copia-segura.sh --help
```

---

## 4. Métodos de backup

### tar

Crea un archivo `.tar.gz` (tar + gzip). Estándar en Linux, buena compresión.

```bash
METHOD="tar"
```

Comando interno: `tar -czf archivo.tar.gz directorio`

Verificación: `tar -tzf archivo.tar.gz`

### zip

Crea un archivo `.zip`. Compatible con Windows y la mayoría de sistemas.

```bash
METHOD="zip"
```

Comando interno: `zip -r archivo.zip directorio`

Verificación: `unzip -t archivo.zip`

### 7z

Crea un archivo `.7z` con compresión LZMA2. La mejor ratio de compresión.

```bash
METHOD="7z"
```

Requiere: `p7zip-full`

Comando interno: `7z a -t7z archivo.7z directorio`

Verificación: `7z t archivo.7z`

### rsync

Backup incremental: solo copia archivos nuevos o modificados.

```bash
METHOD="rsync"
BACKUP_FOLDER="/ruta/destino"
```

Si además se define `ARCHIVE_FOLDER`, después del rsync se comprime el resultado en `.tar.gz`.

Comando interno: `rsync -av --delete origen/ destino/`

---

## 5. Subida externa con rclone

### Configurar rclone

```bash
rclone config
```

Ejemplos de remotos:

| Tipo | Configuración en rclone |
|---|---|
| SFTP | `sftp, host=servidor.com, user=usuario` |
| AWS S3 | `s3, provider=AWS, env_auth=true` |
| Google Drive | `drive, client_id=...` |
| FTP | `ftp, host=ftp.example.com` |

### Activar en el .conf

```bash
REMOTE_ENABLED="true"
REMOTE_DEST="miremoto:/ruta/backups"
REMOTE_OPTS=""  # flags adicionales: --verbose, --progress, etc.
```

### Probar la subida manualmente

```bash
rclone copy /ruta/local/backup.zip miremoto:/ruta/backups/
```

---

## 6. Exclusión de archivos

La variable `EXCLUDE_PATTERNS` acepta patrones separados por espacio. El script adapta la sintaxis según el método:

```bash
EXCLUDE_PATTERNS="*.tmp *.log node_modules .cache"
```

Método | Sintaxis interna
---|---
`tar` | `--exclude=*.tmp --exclude=*.log`
`zip` | `-x *.tmp -x *.log`
`7z` | `-xr!*.tmp -xr!*.log`
`rsync` | `--exclude=*.tmp --exclude=*.log`

---

## 7. Rotación de backups

La variable `RETENTION_DAYS` controla cuántos días se conservan los backups antes de eliminarlos automáticamente.

```bash
RETENTION_DAYS=7  # por defecto
```

La rotación se ejecuta al final de cada backup. Los archivos más antiguos que `RETENTION_DAYS` se eliminan usando `find -mtime`.

Para rsync se aplica sobre todos los archivos en `BACKUP_FOLDER`. Para tar/zip/7z se aplica solo sobre archivos con la extensión correspondiente en `ARCHIVE_FOLDER`.

---

## 8. Programar con cron

```bash
# Abrir crontab
crontab -e

# Ejecutar cada día a las 2:00 AM
0 2 * * * /ruta/completa/bash-copia-segura/copia-segura.sh --config desarrollo-en-curso.conf

# Ejecutar cada 6 horas
0 */6 * * * /ruta/completa/bash-copia-segura/copia-segura.sh --config desarrollo-en-curso.conf
```

**Nota:** Usa siempre rutas absolutas en crontab.

---

## 9. Ejemplos prácticos

### Backup semanal de documentos en ZIP + subida a Google Drive

`configs/documentos.conf`:

```bash
METHOD="zip"
SOURCE="/home/usuario/Documentos"
ARCHIVE_FOLDER="/mnt/backups/documentos"
RETENTION_DAYS=30
REMOTE_ENABLED="true"
REMOTE_DEST="gdrive:Backups/documentos"
EXCLUDE_PATTERNS="*.tmp ~*"
```

### Backup incremental de servidor web + archive comprimido

`configs/webserver.conf`:

```bash
METHOD="rsync"
SOURCE="/var/www"
BACKUP_FOLDER="/mnt/backups/rsync-www"
ARCHIVE_FOLDER="/mnt/backups/archives-www"
RETENTION_DAYS=14
REMOTE_ENABLED="true"
REMOTE_DEST="sftp-server:/backups/www"
EXCLUDE_PATTERNS="node_modules .git cache"
```

### Backup de base de datos (volcado previo + 7z)

Primero crear un script que haga el volcado, luego apuntar SOURCE al directorio de volcados:

```bash
#!/bin/bash
# Pre-backup: volcado de MySQL
mysqldump -u root --all-databases > /tmp/mysql-dump.sql
```

`configs/bd.conf`:

```bash
METHOD="7z"
SOURCE="/tmp"
ARCHIVE_FOLDER="/mnt/backups/bases-datos"
RETENTION_DAYS=7
EXCLUDE_PATTERNS="*.tmp"
```

Ejecutar en orden:

```bash
./pre-backup-db.sh && ./copia-segura.sh --config bd.conf
```

---

## Créditos

**Versión**: v1.0.0

Por **PáginaVIVA**

[Web](https://www.paginaviva.net/) · [GitHub](https://github.com/paginaviva)
