# Diagrama del modelo dimensional - Kent Foods

Esquema estrella. Cada fila del hecho es un producto dentro de una
orden. `Dim_Tiempo` se usa dos veces: FechaOrden y FechaEnvio.

```mermaid
erDiagram
    Dim_Cliente ||--o{ Fact_Detalle_Venta : "ClienteKey"
    Dim_Producto ||--o{ Fact_Detalle_Venta : "ProductoKey"
    Dim_Empleado ||--o{ Fact_Detalle_Venta : "EmpleadoKey"
    Dim_Transportista ||--o{ Fact_Detalle_Venta : "TransportistaKey"
    Dim_Tiempo ||--o{ Fact_Detalle_Venta : "FechaOrdenKey"
    Dim_Tiempo |o--o{ Fact_Detalle_Venta : "FechaEnvioKey"

    Dim_Cliente {
        int ClienteKey PK "sustituta"
        nchar_5 ClienteID UK "clave de negocio"
        nvarchar_40 Empresa
        nvarchar_15 Ciudad
        nvarchar_15 Pais
    }

    Dim_Producto {
        int ProductoKey PK "sustituta"
        int ProductoID UK "clave de negocio"
        nvarchar_40 Producto
        nvarchar_15 Categoria
        nvarchar_40 Proveedor
        nvarchar_15 PaisProveedor
    }

    Dim_Empleado {
        int EmpleadoKey PK "sustituta"
        int EmpleadoID UK "clave de negocio"
        nvarchar_31 NombreEmpleado
        nvarchar_30 Cargo
        nvarchar_15 Pais
        nvarchar_50 Region
    }

    Dim_Transportista {
        int TransportistaKey PK "sustituta"
        int TransportistaID UK "clave de negocio"
        nvarchar_40 Transportista
    }

    Dim_Tiempo {
        int FechaKey PK "AAAAMMDD"
        date Fecha UK
        int Dia
        varchar_10 NombreDiaSemana
        int Mes
        varchar_15 NombreMes
        int AnioMes
        int Trimestre
        int AnioTrimestre
        int Anio
    }

    Fact_Detalle_Venta {
        int OrdenID PK "dimension degenerada"
        int ProductoKey PK,FK
        int FechaOrdenKey FK
        int FechaEnvioKey FK "nullable"
        int ClienteKey FK
        int EmpleadoKey FK
        int TransportistaKey FK
        int Cantidad
        decimal_10_2 PrecioUnitario
        decimal_4_2 Descuento
        decimal_12_2 MontoBruto
        decimal_12_2 MontoDescuento
        decimal_12_2 MontoNeto
        int DiasDespacho "nullable"
    }
```

## Notas

- Las dimensiones tienen clave sustituta (`xxxKey`, IDENTITY) y el ID
  original como clave de negocio (`xxxID`, UNIQUE). El ETL hace Lookup
  por la clave de negocio para llenar el hecho.
- `Dim_Tiempo` usa `AAAAMMDD` como clave (ej. `20170115`) y se llena con
  `dbo.usp_CargarDimTiempo` de 2016 a 2018.
- `OrdenID` es dimensión degenerada.
- Jerarquías para el cubo: Año > Trimestre > Mes > Día (con `AnioMes` y
  `AnioTrimestre` como claves de nivel), Categoría > Producto, Región >
  Empleado.
