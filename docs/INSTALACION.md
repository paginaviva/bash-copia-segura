# Guía de instalación — bash-copia-segura

## Requisitos del sistema

- **Sistema operativo:** Linux (cualquier distribución)
- **Shell:** Bash 4.0 o superior
- **Permisos:** Acceso de lectura al directorio origen, escritura al directorio destino

## Dependencias por método

| Método | Comando | Instalación (Debian/Ubuntu) | Instalación (RHEL/Fedora) |
|---|---|---|---|
| `tar` | `tar` | Preinstalado | Preinstalado |
| `zip` | `zip` | `sudo apt install zip` | `sudo dnf install zip` |
| `7z` | `7z` | `sudo apt install p7zip-full` | `sudo dnf install p7zip` |
| `rsync` | `rsync` | `sudo apt install rsync` | `sudo dnf install rsync` |

## Dependencia para subida externa

| Herramienta | Instalación |
|---|---|
| **rclone** | `sudo -v ; curl https://rclone.org/install.sh \| sudo bash` |

Verificar instalación:

```bash
rclone version
```

Configurar un destino remoto:

```bash
rclone config
# Sigue el asistente para añadir un remoto (S3, SFTP, FTP, Google Drive, etc.)
```

## Instalación del script

```bash
# Opción 1: Clonar el repositorio
git clone https://github.com/tu-usuario/bash-copia-segura.git
cd bash-copia-segura

# Opción 2: Descargar solo los archivos necesarios
mkdir bash-copia-segura && cd bash-copia-segura
wget https://raw.githubusercontent.com/tu-usuario/bash-copia-segura/main/copia-segura.sh
wget https://raw.githubusercontent.com/tu-usuario/bash-copia-segura/main/configs/example.conf
chmod +x copia-segura.sh
mkdir configs logs
```

## Verificar instalación

```bash
cd bash-copia-segura
bash test.sh
```

Todos los tests deben pasar con 0 errores (actualmente **61/61 tests**).

---

## Créditos

**Versión**: v1.0.0

Desarrollado para **PáginaVIVA** — Potenciamos tu estrategia comercial con IA y automatizaciones clave de procesos operativos y visibilidad orgánica en posicionamiento multicanal.

[Web](https://www.paginaviva.net/) · [GitHub](https://github.com/paginaviva)
