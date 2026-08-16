FestTime (iOS + Android)

Proyecto unico para mantener FestTime en ambas plataformas usando una sola fuente de datos de festivales.

Compatibilidad
- iOS 16.0+
- Android 8.0+ (API 26)

Arquitectura del repo
- iOS app nativa: FestTimeApp + FestTime.xcodeproj
- Android app nativa: android/FestTimeAndroid
- Fuente canonica de datos: FestTimeApp/Resources/Festivals
- Salida Android compartida: android/shared-json
- Assets Android finales: android/FestTimeAndroid/app/src/main/assets/festivals

Flujo unificado de datos
1. Edita o anade festivales en FestTimeApp/Resources/Festivals.
2. Ejecuta scripts/sync-shared-json.sh.
3. El script:
    - Actualiza android/shared-json/festivals-catalog.json desde festivals.json.
    - Genera cada archivo android/shared-json/<festival-id>.bundle.json.
    - Copia catalogo y bundles a android/FestTimeAndroid/app/src/main/assets/festivals.
4. Compila iOS y Android con los mismos datos.

Comandos principales
- Sincronizar datos compartidos:
   - ./scripts/sync-shared-json.sh
- Build iOS App Store:
   - ./scripts/build-appstore.sh
- Build Android debug (requiere gradle wrapper):
   - ./scripts/build-android-debug.sh

iOS
- Proyecto listo en FestTime.xcodeproj.
- Ejecutar en Xcode con scheme FestTime.

Android
- Proyecto listo en android/FestTimeAndroid.
- Stack: Kotlin, Jetpack Compose, MVVM, Kotlinx Serialization.
- Funciones clave implementadas:
   - Seleccion de festival.
   - Filtros por dia, turno y escenario.
   - Busqueda por artista.
   - Favoritos persistentes (EncryptedSharedPreferences con fallback).
   - Avisos locales de favoritos a -15, -10 y -5 minutos.
   - Reprogramacion de avisos tras reinicio o actualizacion.

Nota sobre gradle wrapper
- En este entorno no hay comando global gradle instalado, por lo que no se pudo autogenerar gradle wrapper desde terminal.
- Para dejar Android 100% compilable por script, genera wrapper una vez en android/FestTimeAndroid:
   - gradle wrapper --gradle-version 8.7

Formato base de eventos
{
   "id": "unico",
   "dia": "viernes",
   "turno": "noche",
   "hora": "23:10",
   "artista": "Nombre Artista",
   "escenario": "Escenario X"
}
