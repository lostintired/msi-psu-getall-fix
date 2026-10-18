[English](README.md) | [中文](README.zh-CN.md) | **Español** | [Português](README.pt-BR.md) | [Türkçe](README.tr.md)

![MSI Center PSU GET_ALL fix](docs/images/banner.jpg)

# MSI Center: solución para "Read data of PSU GET_ALL fail"

Si tienes una fuente de alimentación MSI con monitorización por USB (como la **MEG Ai1300P**) y usas MSI Center, es muy probable que el registro de Power Supply Unit esté lleno de líneas como esta:

```
10-18-2026 21:50:01.933 | [ERROR] Read data of PSU GET_ALL fail... (6)
```

Aparecen entre 3 y 5 veces por minuto, unas 5000 al día. **Tu fuente y tu USB están bien.** El error viene de un fallo del propio MSI Center, y este repositorio lo parchea.

## Qué falla

Una vez por segundo, MSI Center le pide a la fuente todas sus lecturas (comando `0xE0`, GET_ALL). La respuesta es una lista de valores PMBus LINEAR11: +12V, las corrientes de cada línea, +5V, +3,3V, etc.

La comprobación de la respuesta del módulo (`cPSU.Get` en `API_Power Supply Unit.dll` 1.0.0.38) considera que la respuesta es un error siempre que el byte 3 valga `0xFE`. Esa regla se aplica a todos los comandos. Pero en GET_ALL el byte 3 es el byte bajo de la **lectura de +12V**. Cuando la fuente informa exactamente **11,969 V** (`0xD2FE`), MSI descarta una respuesta perfectamente válida. Reintenta 6 veces seguidas sin pausa, recibe siempre el mismo voltaje y registra `GET_ALL fail`. El número entre paréntesis es un contador de fallos acumulados, no un código de error.

Es decir, la frecuencia del error depende de si tu +12V se queda justo en 11,969 V. No tiene nada que ver con el USB, los cables, AIDA64/HWiNFO/iCUE ni con la carga. Detalles y pruebas: [docs/technical.md](docs/technical.md) (en inglés).

![Why MSI Center logs GET_ALL fail](docs/images/3-cause.png)

## ¿Me afecta?

Ejecuta esto en PowerShell (no hace falta ser administrador):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check-log.ps1
```

Cuenta las líneas `GET_ALL fail` por hora en el registro de hoy.

![PSU log before and after the fix](docs/images/5-log.png)

## Qué hace el parche

Inserta 3 instrucciones IL en `cPSU.Get`: `if (cmd == 0xE0) skip the 0xFE check`. No cambia nada más del módulo, y el resto de comandos conservan la comprobación original.

Medido en una MEG Ai1300P durante 10 minutos:

| | errores en el registro | peticiones GET_ALL | respuestas con +12V = 11,969 V aceptadas |
|---|---|---|---|
| original | 36 | 1199 | 0 |
| parcheado | **0** | **594** (una por segundo) | **67 / 67** |

En la práctica:
- el registro queda limpio;
- no se pierden segundos de lecturas;
- la fuente ya no recibe ráfagas de 6 reintentos.

El comportamiento de la fuente no se toca. El modo single/multi rail, la OCP y los ajustes del ventilador no se ven afectados.

**Este repositorio no contiene ningún archivo de MSI.** El parcheador toma *tu propia* DLL instalada, comprueba su SHA-256 y parchea una copia.

![Errors before and after the fix](docs/images/4-before-after.png)

## La forma más fácil: que lo haga un agente de IA

Si usas un agente de programación con IA (Claude Code, Codex, Cursor, el modo agente de Copilot, etc.), abre la carpeta de este repositorio en él y pega:

```
Lee AGENTS.md en esta carpeta y sigue sus instrucciones para comprobar si mi PC está afectado por el error "GET_ALL fail" de MSI Center y, si lo está, aplicar la solución. Pregúntame antes de cada paso que modifique mi sistema.
```

[AGENTS.md](AGENTS.md) guía al agente por todo el proceso de forma segura:
- revisar el registro;
- verificar el hash del módulo y rechazar las versiones no compatibles;
- instalar el SDK de .NET si hace falta;
- explicar qué se va a cambiar y pedir confirmación antes de hacerlo;
- ejecutar el instalador;
- verificar el resultado.

## Descarga

**Code → Download ZIP** en esta página y extrae el contenido donde quieras. O usa `git clone https://github.com/lostintired/msi-psu-getall-fix`.

## Requisitos

- Windows 10/11 y MSI Center con el componente Power Supply Unit, módulo versión **1.0.0.38**. Las demás versiones se rechazan y no se cambia nada.
- [.NET 10 SDK](https://dotnet.microsoft.com/download), necesario para compilar el parcheador.
- Permisos de administrador.

## Instalación

Ejecuta lo siguiente en PowerShell **como administrador**, desde la carpeta del repositorio:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

El script:
1. comprueba que el módulo es el 1.0.0.38 original (SHA-256 `F7833895…0274BB`);
2. lo copia a `C:\Program Files\MsiPsuGetAllFix\` como copia de seguridad;
3. compila el parcheador, parchea la copia y verifica el resultado (SHA-256 `6535FEB9…5D2B46`; el parche es determinista);
4. sustituye el módulo y reinicia `MSI_Center_Service`. MSI Center vuelve a cargar todos sus componentes, lo que tarda unos segundos;
5. registra la tarea programada **"MSI PSU GET_ALL fix guard"**. Se ejecuta al iniciar sesión y una vez al día:
   - si una actualización de MSI Center ha restaurado el 1.0.0.38 original, vuelve a parchearlo;
   - si aparece una versión *distinta*, no cambia nada y muestra una notificación. Puede que MSI haya corregido el error o que el parcheador necesite actualizarse.

Usa `-NoGuard` para omitir la tarea, o `-MsiCenterDir "D:\...\MSI Center"` si MSI Center no está en la ubicación predeterminada.

Para comprobarlo después: ejecuta `scripts\check-log.ps1` al cabo de unos minutos. No deberían aparecer líneas nuevas posteriores a la hora de la instalación.

## Desinstalación

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\MsiPsuGetAllFix\uninstall.ps1"
```

Esto restaura el módulo original, reinicia el servicio y elimina la tarea y la carpeta de instalación.

## Advertencias

- La firma Authenticode de MSI en la DLL parcheada deja de ser válida. MSI Center no la comprueba (carga los componentes con `Assembly.LoadFile`), pero es posible que el antivirus se queje.
- Solo es compatible el módulo 1.0.0.38. Una futura actualización de MSI puede corregir el error o cambiar el código. En ambos casos, el guardián no toca el módulo nuevo.
- Probado en un único sistema: MEG Ai1300P (USB `VID_0DB0&PID_56D4`), MSI Center 2.0.74.0, SDK 3.2026.0911.01. El mismo fragmento de código se usa en otros dos modelos de fuente (IDs de producto 59209 y 51691). Se agradecen los informes de otros modelos.
- Úsalo bajo tu propia responsabilidad. No tiene ninguna relación con MSI. El error se ha comunicado al soporte de MSI.

## Licencia

MIT para el código de este repositorio. MSI Center y sus componentes pertenecen a MSI.
