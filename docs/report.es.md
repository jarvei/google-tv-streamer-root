# Root operativo en el Google TV Streamer — 2026-11-05

## Resultado

**Conseguido: GS funcional y con root en el mismo arranque.**

- `id -u` → `0`, `getenforce` → `Permissive`.
- `system_server` vivo (pid 685) y `Service window: found`.
- UI funcionando (TDT/Neox en pantalla durante la prueba).
- Agente de root: `kirkwood_root_shell_4035` (pid 13085). El nombre cambia
  en cada ejecución; se lee de `/data/local/tmp/root_agent_ready`.
- `./attach.sh 'id -u; getenforce'` → `0` / `Permissive`.

### Segunda validación (16:19, mismo día)

Repetido sobre un arranque limpio (tras el reinicio que provocó frida-server):
`W1 preserve-initialized` → `W2` → agente `kirkwood_root_shell_13571`,
`id -u`=0, `boot_a` leído (`ANDROID!`), `system_server` 692 vivo y ventana OK,
con un vídeo reproduciéndose. El **capture gate es flaky**: falló 4 intentos
seguidos (`verdict=0`, `near=0`) y pasó al quinto, con el sistema asentado y
un vídeo en marcha. No hubo escritura en los fallos (SELinux seguía Enforcing),
así que reintentar en el mismo arranque es seguro. Subir
`TCL_PERF_WITNESS_ATTEMPTS` a 10 empeoró el patrón; dejar 5.

## La causa del fallo anterior y el arreglo

El exploit tiene una opción propia, `GHOST_SELINUX_PRESERVE_INIT`, que el
wrapper fija a **0**. Con 0, `W1` escribe 8 ceros al principio de
`selinux_state`: deja `enforcing=0` pero también `initialized=0`. El kernel
pierde la policy, `security_sid_to_context_core` falla, binder devuelve
`EINVAL` y `system_server` muere; `init` intenta reiniciar `zygote`, su
`onrestart` falla por el contexto y el framework queda muerto sin retorno.

Con `GHOST_SELINUX_PRESERVE_INIT=1`, `W1` escribe un valor con
`enforcing=0` e `initialized` distinto de cero. SELinux queda Permissive
pero **con la policy cargada**: binder sigue funcionando y `system_server`
sobrevive. El log lo delata:

```
[*] mode 7 armed: plan0 selinux preserve-initialized, plan1 cred, plan2 real_cred
[*] === selinux preserve-initialized (fresh reclaim A) ===
[+] TCL W1 PASS: SELinux disabled via fresh reclaim A (enforce readback=0)
[+] TCL W2 PASS: cred write via fresh reclaim B; victim pid=13080 ...
[+] ROOT AGENT READY: ready pid=13085 abstract=kirkwood_root_shell_4035 selinux=0 pty=1
uid=0(root) ... context=u:r:kernel:s0
```

`selinux_state` está en `0xffffffc00a9d9068` en el vmlinux del aparato
(base + `0x29d9068`); el config confirma `CONFIG_SECURITY_SELINUX_DISABLE` off
y `DEVELOP=y`, así que los bytes son `enforcing`(0), `checkreqprot`(1),
`initialized`(2), `policycap[5]`(3..7).

## Receta que funciona

1. Arranque limpio, SELinux `Enforcing`, sin agente previo.
2. Wrapper parcheado (una línea):

   ```bash
   sed 's/GHOST_SELINUX_PRESERVE_INIT=0/GHOST_SELINUX_PRESERVE_INIT=1/' \
       ghostlock-kirkwood-oneclick.sh > ghostlock-preserve.sh
   adb push ghostlock-preserve.sh /data/local/tmp/
   adb shell 'sh /data/local/tmp/ghostlock-preserve.sh \
       --perf-loops 60000 --settle-us 120000 --exec "id; getenforce"'
   ```

3. **Un solo intento por arranque.** No tocar `zygote` ni `system_server`
   después: con `preserve-init` el framework aguanta; la carga alta del
   spray (load ~50) baja sola.
4. Reengancharse: `./attach.sh '<comando>'`.

## Límites y reglas

- Root **volátil**: se pierde al reiniciar; no hay persistencia (bootloader
  bloqueado, AVB verde, `seccfg` autenticado).
- No matar el proceso `ghostlock-lab` aparcado: mantiene la página de cred
  falsa. El límite de limpieza segura es el reinicio.
- SELinux queda `Permissive` hasta el reinicio; la policy sigue cargada.
- No actualizar la OTA (`google_ota_automatic_download=0` ya puesto).
- El reset por software que funciona incluso con `init` atascado es
  `echo b > /proc/sysrq-trigger` como root (el `reboot` de toybox pasa por
  `init` y no sirve en ese estado).

## Ficheros

- `ghostlock-kirkwood-oneclick.sh` — bundle original (hash `a4968b9b…`).
- Parche: el `sed` de arriba; en el aparato quedó
  `/data/local/tmp/ghostlock-preserve.sh`.
- `reroot.sh` — tras cada reinicio: espera arranque, reintenta el intento hasta
  6 veces (45 s entre intentos) mientras SELinux siga `Enforcing`, y verifica
  root + `system_server`. Si un intento deja SELinux en `Permissive` sin agente,
  aborta y pide reinicio. `./reroot.sh --status` sólo informa; `--attempts N`
  cambia el número de intentos.
- `logs/ghostlock-preserve-2026-11-05.log` — log del intento que funcionó
  (W1/W2/agente).
- `mkzygote.c` — intento de relanzar zygote a mano (no hizo falta; ART aborta
  por `BOOTCLASSPATH`/`No mainline framework library found`).
