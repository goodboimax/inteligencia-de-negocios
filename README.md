# Certamen 2 - Inteligencia de Negocios

## Caso seleccionado
Caso 3: Kent Foods, empresa de venta de alimentos con envío a domicilio.

## Integrantes y sección
- Maximiliano Pozo (@goodboimax)

Trabajo individual, autorizado por el profesor.

Inteligencia de Negocios - UTFSM, paralelo 300, segundo semestre 2026.

## Descripción del problema
La base transaccional (`KentFoods.bak`) tiene órdenes, detalle de
productos, clientes, empleados, transportistas, proveedores y
categorías. Para sacar cualquier indicador hay que cruzar varias tablas
cada vez. La idea es armar un modelo dimensional que deje esa
información lista para consultar y que después sirva para el cubo y el
dashboard de la Fase 2.

## Objetivo del proyecto
- **Fase 1**: definir los KPI, diseñar el modelo dimensional, crearlo en SQL
  Server y cargarlo con un ETL en SSIS desde la base transaccional.
- **Fase 2**: construir el cubo OLAP en SSAS sobre el modelo dimensional y
  desarrollar un dashboard en Power BI orientado a la toma de decisiones.

## KPI definidos
La base no tiene flete, costo de envío ni fecha requerida, así que no
se puede calcular margen ni despachos atrasados. Con lo que hay:

- **Ventas netas** (precio × cantidad × (1 − descuento)): lo que
  realmente se vende después de descuentos. 1.265.792,76 en todo el
  período (jul-2016 a may-2018).
- **Ticket promedio** (ventas netas / órdenes): 1.525 por orden.
- **Días promedio de despacho** (FechaEnvio − FechaOrden): 8,5 días,
  mínimo 1 y máximo 37. Las 21 órdenes sin despachar no entran al
  promedio.
- **% de descuento**: descuentos sobre el monto bruto. 6,5% (88.665,83
  de 1.354.458,59), o sea 107 por orden en promedio.
- **Ventas por empleado**: Peacock es la que más vende (232.891) y
  Buchanan el que menos (68.792).
- **Ventas por categoría y proveedor**: Beverages lidera con el 21% del
  total (267.868).

## Modelo dimensional
Esquema estrella (diagrama en `docs/modelo-dimensional/diagrama.md`).
Categoría y Proveedor quedan dentro de `Dim_Producto` y Región dentro de
`Dim_Empleado`, igual que en los ejercicios Kollao del curso. Así se
hacen menos joins que con copo de nieve.

### Proceso de negocio
Ventas (órdenes) de Kent Foods.

### Granularidad
Una fila por producto dentro de una orden, o sea una fila de
`DetalleOrden`. Es el nivel más fino disponible.

### Dimensiones
- `Dim_Tiempo`: se usa dos veces, para la fecha de orden y la de envío.
- `Dim_Cliente`: quién compra.
- `Dim_Producto`: qué se vende, con categoría y proveedor.
- `Dim_Empleado`: quién vende, con su región.
- `Dim_Transportista`: quién despacha.

Cada dimensión tiene clave sustituta (`ClienteKey`, `ProductoKey`,
etc., `INT IDENTITY`) y guarda el ID original como clave de negocio.
`Dim_Tiempo` usa la fecha como entero `AAAAMMDD` y tiene todos los días
de 2016 a 2018, aunque no haya ventas.

### Tabla de hechos y medidas
`Fact_Detalle_Venta`, con clave `OrdenID + ProductoKey`. `OrdenID` queda
como dimensión degenerada (sirve para contar órdenes).

Medidas: Cantidad, PrecioUnitario, Descuento, MontoBruto,
MontoDescuento, MontoNeto y DiasDespacho. Se usa el precio de
`DetalleOrden` y no el de `Productos`, porque ese es el precio actual
del catálogo y no coincide en 658 de las 2.155 líneas.

Jerarquías pensadas para el cubo: Año > Trimestre > Mes > Día,
Categoría > Producto y Región > Empleado.

### Problemas de la base original
- `Descuento` viene como `real` (0.15000001 en vez de 0.15), se pasa a
  `DECIMAL(4,2)`.
- 21 órdenes (73 líneas) no tienen fecha de envío: `FechaEnvioKey` y
  `DiasDespacho` quedan en NULL.
- Los empleados pueden tener varios territorios, pero siempre de la
  misma región, así que solo se guarda la región.
- `Region` viene con espacios al final (`nchar(50)`), se limpia con
  `RTRIM`.
- Los años 2016 y 2018 están incompletos, conviene comparar por mes o
  trimestre.

## Proceso ETL - Fase 1
Proyecto en `etl/proyecto-ssis/ETL_KentFoods`. El paquete `Maestro.dtsx`
hace todo en orden:

1. **Limpiar SQL** (Execute SQL): borra el hecho y las dimensiones y
   reinicia los IDENTITY (mismo código que `02_limpiar_dw.sql`).
2. `Dim_Transportista`, `Dim_Cliente`, `Dim_Producto`, `Dim_Empleado`:
   un paquete con Data Flow cada uno. Producto une Productos, Categorias
   y Proveedores; Empleado arma el nombre completo con una Derived Column
   y trae la región por Territorios → Regiones.
3. `Dim_Tiempo`: Execute SQL que llama a `usp_CargarDimTiempo` de
   2016-01-01 a 2018-12-31.
4. `Fact_Detalle_Venta`: consulta `DetalleOrden` + `Ordenes` calculando
   montos, días de despacho y las claves de fecha `AAAAMMDD`. Después
   cuatro Lookups cambian `ClienteID`, `EmpleadoID`, `ProductoID` y
   `TransportistaID` por las claves sustitutas.

El orden entre las dimensiones da lo mismo, porque ninguna depende de
otra. Lo que sí importa es limpiar al principio (para que la carga se
pueda repetir) y dejar el hecho al final, porque sus Lookups necesitan
las dimensiones ya cargadas.

### Validación
`database/scripts/03_validar_carga.sql` compara la carga contra los
valores sacados de la base original (19 controles). Resultado de la
última carga: todos OK.

| Tabla | Filas |
|---|---|
| Dim_Cliente | 91 |
| Dim_Producto | 77 |
| Dim_Empleado | 9 |
| Dim_Transportista | 3 |
| Dim_Tiempo | 1.096 |
| Fact_Detalle_Venta | 2.155 |

## Cubo OLAP - Fase 2
Cubo `Kent Foods Ventas` en SSAS Multidimensional (base `KentFoodsCubo`),
construido sobre `KentFoodsDW`. Se crea y procesa con
`olap/scripts/crear_cubo.ps1` (AMO), cuenta con su proyecto de Visual Studio
en `olap/proyecto-ssas/KentFoodsCubo/` y se valida automáticamente contra el DW
con `olap/scripts/validar_cubo.ps1`.

- **Dimensiones y atributos**: Tiempo (como `Fecha Orden` y `Fecha Envio`, con
  `Anio`, `Trimestre`, `Mes`, `Mes del Anio`, `Fecha` y `Dia Semana` ordenados
  cronológicamente; las 21 órdenes sin fecha de envío quedan en `Sin dato`),
  Cliente (`Pais`, `Ciudad` con clave compuesta `(Pais, Ciudad)`, `Empresa`),
  Producto (`Categoria`, `Proveedor`, `Pais Proveedor`, `Producto`), Empleado
  (`Region`, `Pais`, `Cargo`, `Nombre Empleado`) y Transportista.
- **Jerarquías**: Año > Trimestre > Mes > Día, Categoría > Producto,
  País Proveedor > Proveedor > Producto, Región > Empleado y
  País > Ciudad > Empresa.
- **Grupos de medidas**: Ventas (`Cantidad`, `Monto Bruto`, `Monto Descuento`,
  `Monto Neto`, `Lineas Detalle`), Ordenes (`Ordenes` como conteo distinto de
  `OrdenID`) y Despachos (`Ordenes Despachadas` y `Dias Despacho Total` oculta,
  sobre la vista lógica `Fact_Orden` de una fila por orden con
  `IgnoreUnrelatedDimensions = False`).
- **KPI** (miembros calculados en MDX): `Ticket Promedio`, `Pct Descuento`,
  `Descuento Promedio Orden` (`106,83`) y `Dias Promedio Despacho`.

Validado automáticamente con `olap/scripts/validar_cubo.ps1` (35/35 controles
MDX vs SQL OK): ventas netas 1.265.792,76, 830 órdenes (809 despachadas y 21 en
`Sin dato`), ticket 1.525,05, descuento 6,55% (106,83 por orden), despacho
8,49 días, Beverages 267.868,16 y Peacock 232.890,82.

### Revisión y mejoras sobre la Fase 1
Al pasar a la Fase 2 se revisó el proyecto de Fase 1 y se aplicaron cinco
ajustes concretos:

- Corrección del typo en el nombre de la tarea `EXEC Dim_Transportista` dentro
  de `Maestro.dtsx`.
- Creación del script reproducible `database/scripts/04_permisos_ssas.sql`
  para otorgar `db_datareader` en `KentFoodsDW` a
  `NT Service\MSSQLServerOLAPService`.
- Actualización de `docs/modelo-dimensional/diagrama.md` documentando las 5
  jerarquías implementadas en el cubo y la nota de grano sobre `DiasDespacho`.
- Cálculos nombrados en la DSV (`NombreTrimestre`, `NombreMesAnio` y
  `DiaSemanaNum`) y vista lógica `Fact_Orden` para promediar
  `Dias Promedio Despacho` a nivel de orden sin alterar el DDL del DW ni el
  ETL de Fase 1.
- Ajuste de `.gitignore` para versionar `olap/proyecto-ssas/**/*.database` sin
  subir el `.database` de SSIS (`etl/**/*.database`).

## Dashboard Power BI - Fase 2
Archivo `powerbi/dashboard.pbix` conectado en directo (*Live Connection*) al
cubo `Kent Foods Ventas` (`localhost` / `KentFoodsCubo`). Está organizado en
tres páginas:

- **Página 1 (`Resumen de Ventas`)**: 5 tarjetas KPI (`Monto Neto`, `Ordenes`,
  `Ticket Promedio`, `Pct Descuento` y `Dias Promedio Despacho`), filtro de
  `Anio` (sincronizado entre páginas) y `Categoria`, evolución mensual y barras
  por Categoría (con drill-down a Producto), País (con drill-down a Ciudad y
  Empresa) y Empleado.
- **Página 2 (`Despachos y Proveedores`)**: 4 tarjetas (`Ordenes Despachadas`,
  `Dias Promedio Despacho`, `Monto Descuento` y `Cantidad`), días de despacho
  por transportista con línea de promedio en 8,49 días, ventas por país
  proveedor y proveedor (con drill-down), tabla resumen por transportista y
  tabla de estado de envío mostrando las 21 órdenes en `Sin dato`.
- **Página 3 (`Descuentos y Estacionalidad`)**: comparativa mensual entre años
  (`Mes del Anio` × `Anio`, para evitar sesgos al estar 2016 y 2018
  incompletos), ventas y `% Descuento` por categoría, ventas por región y
  empleado (con drill-down) y tabla de ticket promedio y descuentos por
  empleado.

## Tecnologías utilizadas
SQL Server 2019, Visual Studio con SSIS y SSAS (Multidimensional), Power BI
Desktop, PowerShell (AMO/ADOMD.NET), Git/GitHub.

## Estructura del repositorio
```
README.md
docs/modelo-dimensional/            diagrama del modelo
docs/presentacion/                  presentaciones (Fase 1 y Fase 2)
database/scripts/                   01 crear modelo, 02 limpiar, 03 validar, 04 permisos SSAS
database/backup/                    KentFoodsDW.bak
etl/proyecto-ssis/                  proyecto SSIS
olap/scripts/                       crear_cubo.ps1 y validar_cubo.ps1 (cubo SSAS)
olap/proyecto-ssas/KentFoodsCubo/   proyecto SSAS (Visual Studio)
powerbi/dashboard.pbix              dashboard Power BI (Live Connection al cubo)
```

## Instrucciones de ejecución/revisión
Opción rápida: restaurar `database/backup/KentFoodsDW.bak` (SQL Server
2019 o superior), correr `03_validar_carga.sql`, ejecutar
`database/scripts/04_permisos_ssas.sql`, luego
`olap/scripts/crear_cubo.ps1` + `olap/scripts/validar_cubo.ps1`, y abrir
`powerbi/dashboard.pbix` en Power BI Desktop (o `KentFoodsCubo.sln` en Visual
Studio para inspeccionar el cubo).

Para correr todo desde cero:
1. Restaurar `KentFoods.bak` (la base transaccional del caso).
2. Ejecutar `database/scripts/01_crear_modelo.sql`.
3. Abrir `ETL_KentFoods.sln` en Visual Studio y ejecutar `Maestro.dtsx`.
   Las conexiones apuntan a `localhost` con autenticación de Windows.
4. Ejecutar `database/scripts/03_validar_carga.sql` y
   `database/scripts/04_permisos_ssas.sql`.
5. Ejecutar `powershell -ExecutionPolicy Bypass -File olap\scripts\crear_cubo.ps1`
   y validar con `powershell -ExecutionPolicy Bypass -File olap\scripts\validar_cubo.ps1`.
6. Abrir `powerbi/dashboard.pbix` en Power BI Desktop (conectado en directo a
   `localhost / KentFoodsCubo`).

## Distribución de responsabilidades y aportes
| Integrante | Aportes |
|---|---|
| Maximiliano Pozo | **Fase 1**: análisis del caso y KPI, modelo dimensional, scripts SQL, ETL en SSIS, validación y documentación.<br>**Fase 2**: mejoras sobre Fase 1, cubo OLAP en SSAS, proyecto VS, validación MDX, dashboard en Power BI y presentación final. |
