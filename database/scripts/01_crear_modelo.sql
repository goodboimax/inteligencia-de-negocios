-- 01_crear_modelo.sql
-- Certamen 2 - Kent Foods - crea el modelo dimensional en KentFoodsDW
--
-- Grano de Fact_Detalle_Venta: una fila por cada producto dentro de una
-- orden (osea una fila de DetalleOrden en la base original).
-- Dim_Tiempo usa la fecha como clave (no un ID aparte) porque se usa
-- dos veces en el hecho, para FechaOrden y para FechaEnvio.

-- USE KentFoodsDW;
-- GO

IF OBJECT_ID('dbo.Fact_Detalle_Venta', 'U') IS NOT NULL DROP TABLE dbo.Fact_Detalle_Venta;
IF OBJECT_ID('dbo.Dim_Cliente', 'U') IS NOT NULL DROP TABLE dbo.Dim_Cliente;
IF OBJECT_ID('dbo.Dim_Producto', 'U') IS NOT NULL DROP TABLE dbo.Dim_Producto;
IF OBJECT_ID('dbo.Dim_Empleado', 'U') IS NOT NULL DROP TABLE dbo.Dim_Empleado;
IF OBJECT_ID('dbo.Dim_Transportista', 'U') IS NOT NULL DROP TABLE dbo.Dim_Transportista;
IF OBJECT_ID('dbo.Dim_Tiempo', 'U') IS NOT NULL DROP TABLE dbo.Dim_Tiempo;
GO

-- ===================== DIMENSIONES =====================

-- Dim_Cliente: clave = mismo ClienteID de la base origen (nchar(5), tipo Northwind).
CREATE TABLE dbo.Dim_Cliente (
    ClienteID   NCHAR(5)      NOT NULL,
    Empresa     NVARCHAR(40)  NOT NULL,
    Ciudad      NVARCHAR(15)  NULL,
    Pais        NVARCHAR(15)  NULL,
    CONSTRAINT PK_Dim_Cliente PRIMARY KEY (ClienteID)
);
GO

-- Dim_Producto: metemos Categoria y Proveedor aqui adentro en vez de
-- hacerlos tablas aparte (jerarquia Categoria > Producto para el cubo)
CREATE TABLE dbo.Dim_Producto (
    ProductoID     INT           NOT NULL,
    Producto       NVARCHAR(40)  NOT NULL,
    Categoria      NVARCHAR(15)  NOT NULL,
    Proveedor      NVARCHAR(40)  NOT NULL,
    PaisProveedor  NVARCHAR(15)  NULL,
    CONSTRAINT PK_Dim_Producto PRIMARY KEY (ProductoID)
);
GO

-- Dim_Empleado: Region queda como columna de aca (un empleado siempre
-- trabaja en una sola region aunque tenga varios territorios, asi que
-- los territorios no entran al modelo). Jerarquia: Region > Empleado.
CREATE TABLE dbo.Dim_Empleado (
    EmpleadoID      INT           NOT NULL,
    NombreEmpleado  NVARCHAR(31)  NOT NULL,
    Cargo           NVARCHAR(30)  NULL,
    Pais            NVARCHAR(15)  NULL,
    Region          NVARCHAR(50)  NOT NULL,
    CONSTRAINT PK_Dim_Empleado PRIMARY KEY (EmpleadoID)
);
GO

CREATE TABLE dbo.Dim_Transportista (
    TransportistaID  INT           NOT NULL,
    Transportista    NVARCHAR(40)  NOT NULL,
    CONSTRAINT PK_Dim_Transportista PRIMARY KEY (TransportistaID)
);
GO

-- Dim_Tiempo: la clave es la fecha (se reutiliza para FechaOrden y
-- FechaEnvio en el hecho). Jerarquia: Anio > Trimestre > Mes > Dia.
CREATE TABLE dbo.Dim_Tiempo (
    Fecha      DATE         NOT NULL,
    Dia        INT          NOT NULL,
    Mes        INT          NOT NULL,
    NombreMes  VARCHAR(15)  NOT NULL,
    Trimestre  INT          NOT NULL,
    Anio       INT          NOT NULL,
    CONSTRAINT PK_Dim_Tiempo PRIMARY KEY (Fecha)
);
GO

-- ===================== TABLA DE HECHOS =====================

-- Fact_Detalle_Venta: clave primaria OrdenID + ProductoID (grano = una línea
-- de producto dentro de una orden). FechaEnvio y DiasDespacho aceptan NULL
-- porque hay órdenes todavía no despachadas.
CREATE TABLE dbo.Fact_Detalle_Venta (
    OrdenID          INT            NOT NULL,
    ProductoID       INT            NOT NULL,
    FechaOrden       DATE           NOT NULL,
    FechaEnvio       DATE           NULL,
    ClienteID        NCHAR(5)       NOT NULL,
    EmpleadoID       INT            NOT NULL,
    TransportistaID  INT            NOT NULL,
    Cantidad         INT            NOT NULL,
    PrecioUnitario   DECIMAL(10,2)  NOT NULL,
    Descuento        DECIMAL(4,2)   NOT NULL,  -- normalizado desde el real impreciso del origen
    MontoBruto       DECIMAL(12,2)  NOT NULL,  -- Cantidad * PrecioUnitario
    MontoDescuento   DECIMAL(12,2)  NOT NULL,  -- MontoBruto * Descuento
    MontoNeto        DECIMAL(12,2)  NOT NULL,  -- MontoBruto - MontoDescuento (precalculado)
    DiasDespacho     INT            NULL,      -- FechaEnvio - FechaOrden; NULL si no se ha despachado
    CONSTRAINT PK_Fact_Detalle_Venta PRIMARY KEY (OrdenID, ProductoID),
    CONSTRAINT FK_Fact_Cliente        FOREIGN KEY (ClienteID)       REFERENCES dbo.Dim_Cliente (ClienteID),
    CONSTRAINT FK_Fact_Producto       FOREIGN KEY (ProductoID)      REFERENCES dbo.Dim_Producto (ProductoID),
    CONSTRAINT FK_Fact_Empleado       FOREIGN KEY (EmpleadoID)      REFERENCES dbo.Dim_Empleado (EmpleadoID),
    CONSTRAINT FK_Fact_Transportista  FOREIGN KEY (TransportistaID) REFERENCES dbo.Dim_Transportista (TransportistaID),
    CONSTRAINT FK_Fact_FechaOrden     FOREIGN KEY (FechaOrden)      REFERENCES dbo.Dim_Tiempo (Fecha),
    CONSTRAINT FK_Fact_FechaEnvio     FOREIGN KEY (FechaEnvio)      REFERENCES dbo.Dim_Tiempo (Fecha)
);
GO
