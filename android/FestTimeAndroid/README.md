# FestTime Android

Aplicacion Android nativa (Kotlin + Compose) para consumir el catalogo de festivales compartido con iOS.

## Requisitos

- Android Studio Iguana o superior
- JDK 17
- Gradle 8.7 (wrapper recomendado)

## Estructura de datos

La app consume assets en:

- app/src/main/assets/festivals/festivals-catalog.json
- app/src/main/assets/festivals/<festival-id>.bundle.json

Los assets se generan desde los JSON de iOS con:

- scripts/sync-shared-json.sh

## Primer arranque

1. Ejecutar sincronizacion de JSON compartidos:
   - ./scripts/sync-shared-json.sh
2. Generar wrapper (si no existe):
   - cd android/FestTimeAndroid
   - gradle wrapper --gradle-version 8.7
3. Compilar APK debug:
   - ./gradlew assembleDebug

## Funcionalidad implementada

- Seleccion de festival
- Filtro por dia, turno y escenario
- Busqueda por artista
- Favoritos persistentes (EncryptedSharedPreferences con fallback)
- Alertas locales para favoritos a -15, -10 y -5 minutos
- Reprogramacion de alertas al reiniciar dispositivo o actualizar app
