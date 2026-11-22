#!/usr/bin/env bash
# Arranca un AVD en un puerto fijo (si no está ya arrancado) y espera a que termine de bootear.
# Uso: start_emulator.sh <avd_name> <port>
# El dispositivo queda como "emulator-<port>", que es el deviceId usado en launch.json.
set -euo pipefail

AVD="$1"
PORT="$2"
SERIAL="emulator-$PORT"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
EMULATOR="$SDK/emulator/emulator"

is_booted() {
  [ "$("$ADB" -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]
}

if "$ADB" devices | grep -q "^$SERIAL[[:space:]]"; then
  RUNNING_AVD="$("$ADB" -s "$SERIAL" emu avd name 2>/dev/null | head -1 | tr -d '\r')"
  if [ "$RUNNING_AVD" != "$AVD" ]; then
    echo "ERROR: $SERIAL ya está ocupado por el AVD '$RUNNING_AVD' (se esperaba '$AVD')." >&2
    exit 1
  fi
  echo "$AVD ya está arrancado en $SERIAL."
else
  echo "Arrancando $AVD en $SERIAL..."
  # Se lanza en una sesión nueva (setsid vía perl, macOS no trae setsid) para que
  # VS Code no mate el emulador al terminar la tarea preLaunchTask.
  perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' \
    "$EMULATOR" -avd "$AVD" -port "$PORT" </dev/null >/dev/null 2>&1 &
fi

"$ADB" -s "$SERIAL" wait-for-device
echo -n "Esperando a que $AVD termine de arrancar"
for _ in $(seq 1 180); do
  if is_booted; then
    echo " listo."
    exit 0
  fi
  echo -n "."
  sleep 1
done

echo ""
echo "ERROR: timeout esperando a que $AVD arranque." >&2
exit 1
