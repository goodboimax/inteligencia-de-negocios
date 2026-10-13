# Diagrama del modelo dimensional - Kent Foods

Esquema estrella, con `Fact_Detalle_Venta` al medio. Cada fila es un
producto vendido dentro de una orden. `Dim_Tiempo` aparece dos veces
porque se usa tanto para FechaOrden como para FechaEnvio.

```mermaid
erDiagram
    Dim_Cliente ||--o{ Fact_Detalle_Venta : "ClienteID"
    Dim_Producto ||--o{ Fact_Detalle_Venta : "ProductoID"
    Dim_Empleado ||--o{ Fact_Detalle_Venta : "EmpleadoID"
    Dim_Transportista ||--o{ Fact_Detalle_Venta : "TransportistaID"
    Dim_Tiempo ||--o{ Fact_Detalle_Venta : "FechaOrden"
    Dim_Tiempo ||--o{ Fact_Detalle_Venta : "FechaEnvio (x2, misma dimensión)"

    Dim_Cliente {
        nchar_5 ClienteID PK
        nvarchar_40 Empresa
        nvarchar_15 Ciudad
        nvarchar_15 Pais
    }

    Dim_Producto {
        int ProductoID PK
        nvarchar_40 Producto
        nvarchar_15 Categoria
        nvarchar_40 Proveedor
        nvarchar_15 PaisProveedor
    }

    Dim_Empleado {
        int EmpleadoID PK
        nvarchar_31 NombreEmpleado
        nvarchar_30 Cargo
        nvarchar_15 Pais
        nvarchar_50 Region
    }

    Dim_Transportista {
        int TransportistaID PK
        nvarchar_40 Transportista
    }

    Dim_Tiempo {
        date Fecha PK
        int Dia
        int Mes
        varchar_15 NombreMes
        int Trimestre
        int Anio
    }

    Fact_Detalle_Venta {
        int OrdenID PK
        int ProductoID PK
        date FechaOrden FK
        date FechaEnvio FK "nullable"
        nchar_5 ClienteID FK
        int EmpleadoID FK
        int TransportistaID FK
        int Cantidad
        decimal_10_2 PrecioUnitario
        decimal_4_2 Descuento
        decimal_12_2 MontoBruto
        decimal_12_2 MontoDescuento
        decimal_12_2 MontoNeto
        int DiasDespacho "nullable"
    }
```

## Jerarquías para el cubo OLAP (Fase 2)

- Tiempo: Año > Trimestre > Mes > Día
- Producto: Categoría > Producto
- Empleado: Región > Empleado

## Por qué estrella y no copo de nieve

Cada dimensión queda como una sola tabla: Categoría y Proveedor van
dentro de `Dim_Producto`, y Región dentro de `Dim_Empleado`, en vez de
hacerlas tablas aparte. Es más simple de cargar y de consultar (menos
joins), y es el mismo formato que usamos para los ejercicios Kollao del
curso.

## Notas que salieron de revisar la base original

- `Descuento` se normaliza a `DECIMAL(4,2)` en el ETL porque en el origen
  llega como `real` con errores de redondeo (0.15000001 en vez de 0.15).
- `FechaEnvio` y `DiasDespacho` quedan en NULL para las 21 órdenes (73
  líneas de `Fact_Detalle_Venta`) que todavía no se despachan.
- `MontoNeto` se guarda ya calculado (bruto menos descuento) para no
  tener que recalcularlo cada vez.
- Las medidas siempre usan `DetalleOrden.PrecioUnitario`, no
  `Productos.PrecioUnitario` (que es el precio actual), porque en 658 de
  las 2.155 líneas son distintos.
