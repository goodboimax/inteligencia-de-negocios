# Certamen 2 - Inteligencia de Negocios

## Caso seleccionado
Caso 3: Kent Foods (empresa de venta de alimentos con envío a domicilio).

## Integrantes y sección
- _Nombre Apellido_ (@goodboimax)

Trabajo individual, autorizado por el profesor.

Asignatura: Inteligencia de Negocios - UTFSM. Sección: _por completar_. Profesor(a): _por completar_.

## Descripción del problema
Kent Foods vende alimentos con envío a domicilio. La base que nos dieron
(`KentFoods.bak`) tiene las órdenes, el detalle de productos, clientes,
empleados, transportistas, proveedores y categorías, pero para sacar
cualquier número hay que hacer join de varias tablas cada vez. La idea
es armar un modelo dimensional que deje esa información lista para
consultar, y que después sirva de base para el cubo OLAP y el dashboard
de la Fase 2.

## Objetivo del proyecto
En esta fase: diseñar el modelo dimensional, implementarlo en SQL Server
y construir el ETL que lo carga desde la base transaccional. También
definir los KPI que el modelo tiene que poder responder.

## KPI definidos
Elegimos estos seis a partir de lo que se puede calcular con las tablas
que hay (no hay datos de flete, costo de envío ni fecha requerida, así
que no se puede sacar margen ni "despachos atrasados"):

- **Ventas netas** (precio × cantidad × (1 − descuento)): cuánto se
  vende de verdad una vez aplicados los descuentos. Da 1.265.793,29 en
  el período completo (jul-2016 a may-2018).
- **Ticket promedio**: ventas netas ÷ número de órdenes. 1.525 por
  orden.
- **Días promedio de despacho** (FechaEnvio − FechaOrden): 8,5 días en
  promedio, con mínimo 1 y máximo 37. Hay 21 órdenes que todavía no se
  despachan, esas quedan fuera del promedio.
- **% de descuento otorgado**: cuánto se regala en descuentos sobre el
  total bruto. 6,5% (88.665,83 de 1.354.458,59).
- **Ventas por empleado**: para ver quién vende más. Peacock está
  arriba con 232.891, Buchanan más abajo con 68.792.
- **Ventas por categoría y proveedor**: Beverages es la categoría que
  más vende, con 21% del total (267.868).

Nos quedó pendiente un séptimo (demora por transportista: Federal
Shipping 7,5 días, Speedy Express 8,6, United Package 9,2) pero con
seis alcanza para el proyecto.

## Modelo dimensional

Usamos esquema **estrella** (diagrama en `docs/modelo-dimensional/diagrama.md`).
Categoría y Proveedor quedan dentro de `Dim_Producto`, y Región dentro de
`Dim_Empleado`, en vez de hacerlas tablas aparte. Es el mismo formato que
se usó en los ejercicios Kollao del curso y necesita menos joins que un
copo de nieve.

Los 4 pasos de Kimball, aplicados a este caso:

### Proceso de negocio
Las ventas de alimentos con envío (órdenes) de Kent Foods.

### Granularidad
Un registro por cada producto vendido dentro de una orden, o sea una
fila de `DetalleOrden` en la base original. Es el detalle más fino que
se puede sacar.

### Dimensiones
Tiempo (¿cuándo?, se usa dos veces: FechaOrden y FechaEnvio), Cliente
(¿quién compra?), Producto (¿qué?, con categoría y proveedor adentro),
Empleado (¿quién vende?, con región adentro) y Transportista (¿quién
despacha?).

Cada dimensión tiene una **clave sustituta** (`ClienteKey`,
`ProductoKey`, etc., `INT IDENTITY`) generada por el DW, y guarda el ID
de la base original como clave de negocio (`ClienteID`, `ProductoID`,
etc.). `Dim_Tiempo` usa como clave la fecha en entero `AAAAMMDD` y es un
calendario continuo (2016–2018, todos los días aunque no haya ventas),
con columnas `AnioMes` y `AnioTrimestre` para que la jerarquía funcione
en el cubo.

### Tabla de hechos y medidas
La tabla de hechos es `Fact_Detalle_Venta`, con clave primaria
`OrdenID + ProductoKey` (`OrdenID` queda como dimensión degenerada) y
una foránea a la clave sustituta de cada dimensión.

Medidas: Cantidad, PrecioUnitario, MontoBruto, MontoDescuento,
MontoNeto (ya calculado como bruto menos descuento) y DiasDespacho. Se
calculan siempre con el precio que quedó guardado en `DetalleOrden`, no
con el de `Productos` (que es el precio actual del catálogo), porque en
658 de las 2.155 líneas son distintos.

Para el cubo de la Fase 2 identificamos estas jerarquías: Tiempo va
Año > Trimestre > Mes > Día, Producto va Categoría > Producto y Empleado
va Región > Empleado.

Cosas de la base original que hubo que resolver antes de armar el
modelo:
- El `Descuento` llega como `real` y queda con errores de redondeo
  (0.15000001 en vez de 0.15), así que en el ETL se convierte a
  `DECIMAL(4,2)`.
- 21 órdenes (73 líneas del hecho) todavía no se despachan, entonces
  `FechaEnvioKey` y `DiasDespacho` quedan en NULL para esas.
- Un empleado puede tener varios territorios, pero siempre de la misma
  región, así que a `Dim_Empleado` le pusimos `Region` directamente y
  dejamos los territorios fuera.
- `Region` y `Territorio` vienen con hartos espacios en blanco al final
  (son `nchar(50)`), eso se limpia con `RTRIM` en el ETL.
- Revisamos la integridad de la base original (sin huérfanas, sin
  duplicados, sin fechas de envío antes que la orden) y está bien.
- Las órdenes van de jul-2016 a may-2018, pero esos dos años están
  incompletos, así que las comparaciones hay que hacerlas por mes o
  trimestre, no por año.

## Proceso ETL - Fase 1
El flujo de control primero borra el destino (el hecho antes que las
dimensiones, por las foráneas) y después carga en este orden:
`Dim_Transportista → Dim_Cliente → Dim_Producto → Dim_Empleado →
Dim_Tiempo → Fact_Detalle_Venta`.

- **Dim_Transportista** sale directo de `Transportistas`, sin cambios.
- **Dim_Cliente** sale de `Clientes`, ordenado por `ClienteID`.
- **Dim_Producto** sale de una consulta que une `Productos` con
  `Categorias` y `Proveedores`.
- **Dim_Empleado** sale de `Empleados` unido a su región (a través de
  `Territorios` → `Regiones`, con DISTINCT y RTRIM), y se arma
  `NombreEmpleado` juntando nombre y apellido.
- **Dim_Tiempo** se llena ejecutando `dbo.usp_CargarDimTiempo` (una
  tarea *Execute SQL*) con el rango 01-01-2016 a 31-12-2018, que cubre
  todas las fechas de orden y de envío.
- **Fact_Detalle_Venta** sale de `DetalleOrden` unido a `Ordenes`,
  calculando los montos, `DiasDespacho` y convirtiendo el descuento a
  `DECIMAL`. Después pasa por un *Lookup* contra cada dimensión para
  cambiar los ID del origen por las claves sustitutas (`ClienteID` →
  `ClienteKey`, etc.; las fechas → `FechaKey`).

Una carga de prueba contra la versión anterior del esquema (antes de las
claves sustitutas) dio los números que esperábamos: 830 órdenes, 51.317
unidades, 1.354.458,59 de bruto, 88.665,83 de descuento, 1.265.793,29 de
neto, 91 clientes, 77 productos, 9 empleados y 3 transportistas. Con el
calendario continuo, `Dim_Tiempo` pasa a tener 1.096 fechas. Hay que
repetir esta validación con la carga de SSIS.
Falta armar los paquetes `.dtsx` en SSIS que hagan esta misma carga (eso
va en Visual Studio, en Windows): un paquete por tabla más uno maestro
que los ejecuta en orden.

## Cubo OLAP - Fase 2
_Pendiente (Fase 2)._

## Dashboard Power BI - Fase 2
_Pendiente (Fase 2)._

## Tecnologías utilizadas
SQL Server, Visual Studio (SSIS, SSAS), Power BI, Git/GitHub.

## Estructura del repositorio
```
README.md
docs/modelo-dimensional/   diagrama y documentación del modelo
docs/presentacion/         presentación de cada fase
database/scripts/          scripts SQL del modelo dimensional
database/backup/           backup (.bak) de la BD dimensional
etl/proyecto-ssis/         proyecto SSIS
olap/proyecto-ssas/        proyecto SSAS (Fase 2)
powerbi/                   dashboard .pbix (Fase 2)
```

## Instrucciones de ejecución/revisión
_Por completar._

## Distribución de responsabilidades y aportes
| Integrante | Aportes principales |
|---|---|
| _Nombre_ | _por completar_ |
