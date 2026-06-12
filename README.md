# 🐴 El Alazán Agroalimentos — Punto de Venta Offline

> Bienvenido a tu proyecto de Punto de Venta Offline, Luis :D
>
> Un Mini-CRM y POS de alta velocidad para venta de insumos agrícolas,
> veterinaria y semillas en zonas rurales. Funciona **100% sin internet**
> y sincroniza solo cuando hay señal.

---

## ✨ Qué hace

| Módulo | Descripción |
|---|---|
| **Mostrador** | Pantalla dividida: catálogo visual a la izquierda, ticket a la derecha. 1 toque = 1 artículo al carrito. Cobro en 2 toques con cambio calculado. |
| **Pedidos** | Pedidos por WhatsApp/teléfono en **3 pasos desde el carrito** (cliente → repartidor → confirmar). Máquina de estados: `Pendiente → Asignado → Completado` (+ cancelación con devolución de stock). |
| **Clientes (CRM)** | Perfil comercial por cliente: categoría (Minorista/Mayorista), **descuento base que se aplica solo** al asignarlo a la venta (anulable), historial `total_spent`/compras acumulado al cobrar, y analítica local: top de compradores, ventas por canal y categorías — todo en SQLite, sin nube. |
| **Variantes (SKUs)** | Producto padre con presentaciones independientes (Costal 50 kg / Granel kg), cada una con SKU, precio, **stock propio** y **precios escalonados por volumen**. **Pasar a granel**: abrir un costal acredita su equivalente en la presentación granel (se puede crear ahí mismo), atómico; venta por % del costal o por unidad exacta. **Regateo**: precio manual por línea con precio de lista auditado, y descuento del ticket por % o monto. |
| **Inventario** | Las variantes descuentan stock; servicios (flete, consulta veterinaria) se cobran sin tocar inventario. Ajustes +/- de un toque por presentación y alta exprés. |
| **Resumen** | Flujo de caja del día: ventas cobradas, **utilidad neta**, ticket promedio, top de vendidos y salud de la sincronización. |
| **Excel** | **Importación** de catálogo/clientes desde `.xlsx`/`.csv` con asistente de mapeo de columnas (funciona con cualquier formato de hoja), y **exportación** de reportes `.xlsx` con 3 hojas: Ventas, Detalle por artículo e Inventario valorizado. |
| **Sincronización** | Outbox Pattern: cada operación queda en cola local y se envía **por lotes y en silencio** cuando hay conexión. UUID v4 de cliente en todo registro. |

Para usar el logotipo real coloca el archivo en `assets/branding/logo.png` (mientras no exista se muestra un monograma dorado de la marca).

El primer arranque siembra un catálogo de demostración (semillas,
fertilizantes, veterinaria, fletes…) para que puedas vender desde el
minuto uno.

## 🚀 Cómo correrlo (VS Code)

Requisitos: [Flutter](https://docs.flutter.dev/get-started/install) 3.22+
(canal stable).

```bash
git clone <este-repo>
cd <carpeta-del-repo>

# 1. Genera las carpetas de plataforma (android/, windows/, ...)
#    El nombre del proyecto DEBE ser "agropos":
flutter create . --project-name agropos --platforms windows,android,linux,macos

# 2. Dependencias
flutter pub get

# 3. ¡A vender!
flutter run -d windows     # o: -d linux / -d macos / tu dispositivo Android
```

Pruebas y análisis estático:

```bash
flutter test
flutter analyze
```

### Conectar un backend (opcional)

Sin configurar nada, la app trabaja en **modo local** y acumula la cola.
Cuando exista una API central (Laravel/Node/lo que sea):

```bash
flutter run --dart-define=AGROPOS_API_URL=https://mi-servidor.com
```

## 🏛️ Arquitectura (Clean Architecture)

```
lib/
├── core/                      # Compartido: config, tema, utilidades
│   ├── config/app_config.dart
│   ├── db/app_database.dart   # SQLite: esquema + seed + llave-valor
│   ├── errors/failures.dart   # Fallas tipadas de dominio
│   ├── network/connectivity_service.dart
│   ├── theme/app_theme.dart
│   └── utils/                 # Result<T>, Money (centavos), UUID, folio…
│
├── domain/                    # ❤️ Reglas de negocio (Dart puro, sin Flutter)
│   ├── entities/              # Transaction, Product, Service, SyncQueue,
│   │                          # Customer, DeliveryPerson, CartLine
│   ├── repositories/          # Contratos (puertos): qué necesita el negocio
│   └── usecases/              # ProcessTransaction, AssignOrder, CompleteOrder,
│                              # CancelOrder, SyncPendingOperations, SalesSummary
│
├── data/                      # Implementaciones (adaptadores)
│   ├── models/                # Mappers entidad ⇄ fila SQLite / JSON snake_case
│   ├── repositories/          # SQLite con transacciones atómicas + Outbox
│   ├── remote/                # HttpSyncGateway (API REST agnóstica)
│   └── sync/sync_engine.dart  # Conectividad + timer + drenado por lotes
│
└── presentation/              # UI (Flutter + Riverpod)
    ├── providers.dart         # Composition root (inyección de dependencias)
    ├── state/cart_controller.dart  # Carrito persistente (sobrevive cierres)
    ├── screens/
    │   ├── home_shell.dart    # NavigationRail (PC) / NavigationBar (teléfono)
    │   ├── pos/               # Split-screen + cobro + flujo de reparto 3 pasos
    │   ├── orders/            # Tablero de la máquina de estados
    │   ├── inventory/         # Stock, márgenes, alta exprés
    │   └── dashboard/         # Métricas financieras del día
    └── widgets/sync_status_chip.dart
```

**Regla de dependencia:** `presentation → domain ← data`. El dominio no
importa Flutter ni SQLite ni HTTP; por eso las pruebas de negocio corren
con fakes puros (ver `test/domain/`).

### Decisiones clave

- **Dinero en centavos (`int`)** — nunca `double` para finanzas: cero
  errores de redondeo en `precio_costo`, `precio_venta`, `utilidad_neta`.
- **UUID v4 generado en el cliente** para ventas, pedidos, clientes,
  catálogo y cola: dos sucursales offline jamás colisionan al sincronizar.
- **Snapshot de precios por línea**: cambiar un precio en el catálogo no
  reescribe la historia financiera.
- **Atomicidad real**: venta + descuento de stock + movimiento de
  inventario + entrada del Outbox se escriben en **una sola transacción
  SQLite**. Si algo falla, no queda nada a medias.
- **Outbox con backoff exponencial** (1, 2, 4… máx 30 min) e idempotencia
  por UUID de operación; tras 8 intentos pasa a `error` para reintento
  manual desde el Resumen.

## 🔌 Contrato del backend (para implementarlo después)

Un solo endpoint recibe los lotes:

```
POST /api/v1/sync/batch
Content-Type: application/json

{
  "device_id": "uuid-del-dispositivo",
  "enviado_en": "2026-06-10T12:00:00Z",
  "operaciones": [
    {
      "id": "uuid-de-la-operacion",        // clave de idempotencia
      "entidad": "transaccion",            // transaccion|catalogo|cliente|repartidor
      "entidad_id": "uuid-del-registro",
      "operacion": "create",               // create|update
      "creado_en": "2026-06-10T11:58:03Z",
      "payload": { /* registro completo en snake_case */ }
    }
  ]
}
```

Respuesta esperada (HTTP 200):

```json
{
  "resultados": [
    { "id": "uuid-de-la-operacion", "ok": true,  "mensaje": null },
    { "id": "otra-operacion",       "ok": false, "mensaje": "motivo" }
  ]
}
```

Reglas para el servidor: **upsert por `entidad_id`** (los `update` pueden
llegar antes que su `create` si un lote anterior falló a medias) y
**descartar `id` de operación ya procesados** (reintentos del cliente).

## 📊 Importar y exportar Excel

**Importar** (Inventario → botón ⬆️): elige `.xlsx` o `.csv`, el asistente
detecta las columnas por su encabezado y tú confirmas el mapeo
("esta columna es Nombre, esta es Precio venta…"). Los artículos con el
mismo nombre se **actualizan** (precios/stock/categoría); los nuevos se
crean con UUID. Nada se borra y todo queda encolado para sincronizar.
Los clientes se deduplican por teléfono o nombre.

> Nota: el `.xls` antiguo no es soportado — en Excel usa *Guardar como →
> .xlsx o CSV*. Los CSV con `;` (Excel en español), BOM y saltos de línea
> de Windows se detectan solos. Formato de números esperado: `1,750.50`.

**Exportar** (Resumen → "Exportar a Excel"): elige rango (hoy / 7 días /
mes / todo) y guarda un `.xlsx` con hojas **Ventas** (una fila por
transacción con subtotal, descuento, total, costo y utilidad neta, más
fila de totales), **Detalle** (una fila por artículo vendido, lista para
tablas dinámicas) e **Inventario** (catálogo valorizado a costo).

## 🗺️ Siguientes pasos sugeridos

- [ ] Impresión de tickets (ESC/POS por Bluetooth/USB).
- [ ] Cuentas por cobrar (fiado) por cliente.
- [ ] Sincronización descendente (catálogo administrado desde el servidor).
- [ ] Multi-sucursal con reportes consolidados.
- [ ] Modo oscuro y accesos rápidos de teclado para escritorio.
