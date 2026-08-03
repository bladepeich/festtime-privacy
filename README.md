FestTime iOS (SwiftUI)

Compatibilidad
- iOS 16.0 o superior
- iPhone y iPad

Objetivo
- App iOS preparada para multiples festivales.
- Cada festival se define por metadatos, eventos y colores de escenarios en JSON.
- Incluye todas las funciones del HTML original: dias, turno dia/noche, filtro por escenario, buscador, favoritos y vista de favoritos agrupada por dia.
- Incluye avisos locales con alarma para favoritos a 15, 10 y 5 minutos antes.

Estructura
- FestTimeApp/Sources/App: entrada de la app
- FestTimeApp/Sources/Domain: modelos de dominio
- FestTimeApp/Sources/Data: carga de recursos JSON
- FestTimeApp/Sources/Features/Schedule: UI y estado de horarios
- FestTimeApp/Sources/Features/Shared: utilidades de UI
- FestTimeApp/Resources/Festivals: catalogo y datos de festivales

Recursos actuales
- festivals.json: catalogo multi-festival (ahora con Sonorama 2026)
- sonorama-2026-events.json: 184 eventos
- sonorama-2026-stage-colors.json: colores de escenario

Como ejecutarlo en Xcode
1. Crea un proyecto nuevo en Xcode:
   - iOS App
   - Nombre: FestTime
   - Interface: SwiftUI
   - Language: Swift
2. Reemplaza los archivos Swift generados por los de FestTimeApp/Sources.
3. Arrastra FestTimeApp/Resources/Festivals al target principal (Copy items if needed) y marca Target Membership.
4. Ejecuta en simulador o dispositivo.

Escalar a muchos festivales
- La alta de nuevos festivales es una tarea interna de desarrollo.
- Los festivales nuevos se incluyen en cada nueva version de la app y llegan al usuario por actualizacion.
- No existe alta manual desde la app final.

Flujo interno para anadir festivales (mantenimiento)
1. Duplica los archivos JSON de ejemplo con nuevo id (por ejemplo, bbk-2027-events.json y bbk-2027-stage-colors.json).
2. Agrega una entrada nueva en festivals.json con:
   - id, name, year
   - days (incluyendo calendarDate)
   - defaultDayID y defaultShift
   - forcedShiftByDay (opcional)
   - eventsFile y stageColorsFile
3. Publica una nueva version de la app con esos recursos incluidos en el bundle.

Formato de eventos
Cada item debe seguir esta forma:
{
  "id": "unico",
  "dia": "viernes",
  "turno": "noche",
  "hora": "23:10",
  "artista": "Nombre Artista",
  "escenario": "Escenario X"
}

Formato de dias en festivals.json
{
   "id": "viernes",
   "displayName": "Vie 7",
   "calendarDate": "2026-08-07"
}

Notas de persistencia
- La app guarda en UserDefaults por festival:
  - dia seleccionado
  - turno seleccionado
  - escenario seleccionado
  - texto de busqueda
  - favoritos
   - avisos favoritos activados/desactivados
- Los favoritos no se pierden al actualizar la app (si el usuario no desinstala).
- Si en una version futura cambias el id de un festival o ids de eventos, puedes migrarlos con:
   - legacyIDs en el festival
   - favoriteIDAliases para mapear ids antiguos de eventos a ids nuevos

Avisos de favoritos
- Boton en cabecera: "Avisos ON/OFF".
- Al activarlo, la app solicita permisos de notificaciones.
- Se programan recordatorios para cada favorito futuro a -15, -10 y -5 minutos.
- Cada aviso incluye sonido de alarma del sistema.
- Si quitas o anades favoritos, los avisos se reprograman automaticamente.
