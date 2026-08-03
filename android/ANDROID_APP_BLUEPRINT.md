# FestTime Android Blueprint

## Objetivo
Replicar la app iOS en Android usando la misma base de datos JSON por festival.

## Stack recomendado
- Kotlin
- Jetpack Compose
- MVVM
- Kotlin Coroutines + Flow
- Kotlinx Serialization (JSON)
- DataStore (preferencias UI)
- Room (cache opcional)
- WorkManager (resincronizaciones)
- AlarmManager + NotificationManager (avisos -15, -10, -5)

## Estructura de proyecto
- app/
- data/
- domain/
- feature/schedule/
- feature/favorites/
- feature/settings/
- resources/festivals/

## Modelos base compartidos
- FestivalCatalog
- FestivalDefinition
- FestivalDay
- FestivalMenuOption
- FestivalEvent

## Contratos JSON
Cada festival se trabaja en un unico archivo bundle:
- festival: metadatos del festival
- stageColors: mapa escenario -> color
- events: lista de conciertos

Archivo sugerido por festival:
- <festival-id>.bundle.json

## Flujo de carga
1. Cargar catalogo desde festivals-catalog.json.
2. Al seleccionar festival, cargar <festival-id>.bundle.json.
3. Pintar dias, turno, escenario y lista filtrada.
4. Persistir estado por festival (dia, turno, escenario, busqueda, favoritos, alertas).

## Filtros y ordenacion
- Filtros:
  - dia
  - turno
  - escenario
  - busqueda por artista (normalizada)
- Orden:
  - hora de inicio ascendente
  - artista ascendente

Nota: la hora puede venir como rango "HH:mm - HH:mm". Parsear solo la hora de inicio.

## Favoritos: requisito critico
- No perder favoritos bajo ningun concepto.
- Persistencia redundante recomendada:
  - Principal: EncryptedSharedPreferences o SQLCipher/Room cifrado
  - Respaldo: Auto Backup Android + export/import manual JSON
- Clave por festival:
  - festtime.favorites.<festival-id>

## Alertas
- Programar avisos locales para favoritos:
  - 15 min antes
  - 10 min antes
  - 5 min antes
- Reprogramar cuando cambian favoritos o al iniciar app.
- Cancelar avisos de eventos pasados.

## Menu hamburguesa
Orden recomendado:
1. Seleccionar festival
2. Activar/Desactivar alertas
3. Nombre del festival seleccionado
4. Opciones del festival (menuOptions)
   - Si tiene inAppImageURL: abrir visor interno con zoom
   - Si tiene url: abrir Custom Tab/WebView

## Paridad visual minima con iOS
- Cabecera con degradado ancho completo
- Logo en cabecera
- Favoritos visibles
- Visor de plano/acampada interno con zoom voluntario

## Integracion de nuevos festivales
1. Recibir un JSON en formato bundle.
2. Guardarlo en resources/festivals/<id>.bundle.json.
3. Anadir/actualizar entrada en festivals-catalog.json.
4. Recompilar.

## Formato de bundle (resumen)
{
  "festival": { ... },
  "stageColors": { ... },
  "events": [ ... ]
}
