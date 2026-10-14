-- 01_crear_modelo.sql
-- Certamen 2 - Kent Foods - crea el modelo dimensional en KentFoodsDW
--
-- Grano de Fact_Detalle_Venta: una fila por cada producto dentro de una
-- orden (osea una fila de DetalleOrden en la base original).
--
-- Todas las dimensiones tienen clave sustituta (xxxKey, IDENTITY) propia
-- del DW, y guardan el ID de la base origen como clave de negocio (xxxID)
-- para que el ETL pueda hacer el Lookup al cargar el hecho.
-- Dim_Tiempo es la excepcion: su clave es la fecha como entero AAAAMMDD
-- (inteligente, pero no depende del origen) y se llena con el procedimiento
-- dbo.usp_CargarDimTiempo como calendario continuo.
--
-- Se puede ejecutar completo de una vez: crea la base si no existe.

IF DB_ID('KentFoodsDW') IS NULL CREATE DATABASE KentFoodsDW;
GO
USE KentFoodsDW;
GO

IF OBJECT_ID('dbo.Fact_Detalle_Venta', 'U') IS NOT NULL DROP TABLE dbo.Fact_Detalle_Venta;
IF OBJECT_ID('dbo.Dim_Cliente', 'U') IS NOT NULL DROP TABLE dbo.Dim_Cliente;
IF OBJECT_ID('dbo.Dim_Producto', 'U') IS NOT NULL DROP TABLE dbo.Dim_Producto;
IF OBJECT_ID('dbo.Dim_Empleado', 'U') IS NOT NULL DROP TABLE dbo.Dim_Empleado;
IF OBJECT_ID('dbo.Dim_Transportista', 'U') IS NOT NULL DROP TABLE dbo.Dim_Transportista;
IF OBJECT_ID('dbo.Dim_Tiempo', 'U') IS NOT NULL DROP TABLE dbo.Dim_Tiempo;
IF OBJECT_ID('dbo.usp_CargarDimTiempo', 'P') IS NOT NULL DROP PROCEDURE dbo.usp_CargarDimTiempo;
GO

-- ===================== DIMENSIONES =====================

-- Dim_Cliente: ClienteID es el nchar(5) de la base origen (tipo Northwind).
CREATE TABLE dbo.Dim_Cliente (
    ClienteKey  INT IDENTITY(1,1) NOT NULL,
    ClienteID   NCHAR(5)      NOT NULL,
    Empresa     NVARCHAR(40)  NOT NULL,
    Ciudad      NVARCHAR(15)  NULL,
    Pais        NVARCHAR(15)  NULL,
    CONSTRAINT PK_Dim_Cliente PRIMARY KEY (ClienteKey),
    CONSTRAINT UQ_Dim_Cliente_ClienteID UNIQUE (ClienteID)
);
GO

-- Dim_Producto: metemos Categoria y Proveedor aqui adentro en vez de
-- hacerlos tablas aparte (jerarquia Categoria > Producto para el cubo)
CREATE TABLE dbo.Dim_Producto (
    ProductoKey    INT IDENTITY(1,1) NOT NULL,
    ProductoID     INT           NOT NULL,
    Producto       NVARCHAR(40)  NOT NULL,
    Categoria      NVARCHAR(15)  NOT NULL,
    Proveedor      NVARCHAR(40)  NOT NULL,
    PaisProveedor  NVARCHAR(15)  NULL,
    CONSTRAINT PK_Dim_Producto PRIMARY KEY (ProductoKey),
    CONSTRAINT UQ_Dim_Producto_ProductoID UNIQUE (ProductoID)
);
GO

-- Dim_Empleado: Region queda como columna de aca (un empleado siempre
-- trabaja en una sola region aunque tenga varios territorios, asi que
-- los territorios no entran al modelo). Jerarquia: Region > Empleado.
CREATE TABLE dbo.Dim_Empleado (
    EmpleadoKey     INT IDENTITY(1,1) NOT NULL,
    EmpleadoID      INT           NOT NULL,
    NombreEmpleado  NVARCHAR(31)  NOT NULL,
    Cargo           NVARCHAR(30)  NULL,
    Pais            NVARCHAR(15)  NULL,
    Region          NVARCHAR(50)  NOT NULL,
    CONSTRAINT PK_Dim_Empleado PRIMARY KEY (EmpleadoKey),
    CONSTRAINT UQ_Dim_Empleado_EmpleadoID UNIQUE (EmpleadoID)
);
GO

CREATE TABLE dbo.Dim_Transportista (
    TransportistaKey  INT IDENTITY(1,1) NOT NULL,
    TransportistaID   INT           NOT NULL,
    Transportista     NVARCHAR(40)  NOT NULL,
    CONSTRAINT PK_Dim_Transportista PRIMARY KEY (TransportistaKey),
    CONSTRAINT UQ_Dim_Transportista_TransportistaID UNIQUE (TransportistaID)
);
GO

-- Dim_Tiempo: se usa dos veces en el hecho (FechaOrden y FechaEnvio).
-- Jerarquia: Anio > Trimestre > Mes > Dia. Mes y Trimestre se repiten
-- todos los anios, por eso van tambien AnioTrimestre (20171) y AnioMes
-- (201701), que sirven de clave unica para cada nivel en el cubo.
CREATE TABLE dbo.Dim_Tiempo (
    FechaKey        INT          NOT NULL,  -- AAAAMMDD, ej. 20170115
    Fecha           DATE         NOT NULL,
    Dia             INT          NOT NULL,
    NombreDiaSemana VARCHAR(10)  NOT NULL,
    Mes             INT          NOT NULL,
    NombreMes       VARCHAR(15)  NOT NULL,
    AnioMes         INT          NOT NULL,
    Trimestre       INT          NOT NULL,
    AnioTrimestre   INT          NOT NULL,
    Anio            INT          NOT NULL,
    CONSTRAINT PK_Dim_Tiempo PRIMARY KEY (FechaKey),
    CONSTRAINT UQ_Dim_Tiempo_Fecha UNIQUE (Fecha)
);
GO

-- Llena Dim_Tiempo con todos los dias entre @Desde y @Hasta (sin huecos,
-- aunque ese dia no haya ventas). Los nombres se arman con CASE para no
-- depender del idioma del servidor (DATENAME saldria en ingles).
CREATE PROCEDURE dbo.usp_CargarDimTiempo
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.Dim_Tiempo;

    DECLARE @f DATE = @Desde;
    WHILE @f <= @Hasta
    BEGIN
        INSERT INTO dbo.Dim_Tiempo
            (FechaKey, Fecha, Dia, NombreDiaSemana, Mes, NombreMes,
             AnioMes, Trimestre, AnioTrimestre, Anio)
        VALUES (
            CONVERT(INT, CONVERT(CHAR(8), @f, 112)),
            @f,
            DAY(@f),
            -- 1900-01-01 fue lunes, asi no depende de SET DATEFIRST
            CASE DATEDIFF(DAY, '19000101', @f) % 7
                WHEN 0 THEN 'Lunes'   WHEN 1 THEN 'Martes' WHEN 2 THEN 'Miercoles'
                WHEN 3 THEN 'Jueves'  WHEN 4 THEN 'Viernes' WHEN 5 THEN 'Sabado'
                ELSE 'Domingo' END,
            MONTH(@f),
            CASE MONTH(@f)
                WHEN 1 THEN 'Enero'      WHEN 2 THEN 'Febrero'  WHEN 3 THEN 'Marzo'
                WHEN 4 THEN 'Abril'      WHEN 5 THEN 'Mayo'     WHEN 6 THEN 'Junio'
                WHEN 7 THEN 'Julio'      WHEN 8 THEN 'Agosto'   WHEN 9 THEN 'Septiembre'
                WHEN 10 THEN 'Octubre'   WHEN 11 THEN 'Noviembre' ELSE 'Diciembre' END,
            YEAR(@f) * 100 + MONTH(@f),
            DATEPART(QUARTER, @f),
            YEAR(@f) * 10 + DATEPART(QUARTER, @f),
            YEAR(@f)
        );
        SET @f = DATEADD(DAY, 1, @f);
    END
END
GO

-- ===================== TABLA DE HECHOS =====================

-- Fact_Detalle_Venta: clave primaria OrdenID + ProductoKey (grano = una
-- linea de producto dentro de una orden). OrdenID queda como dimension
-- degenerada (no tiene tabla propia, solo agrupa las lineas de una orden).
-- FechaEnvioKey y DiasDespacho aceptan NULL porque hay ordenes todavia
-- no despachadas.
CREATE TABLE dbo.Fact_Detalle_Venta (
    OrdenID           INT            NOT NULL,
    ProductoKey       INT            NOT NULL,
    FechaOrdenKey     INT            NOT NULL,
    FechaEnvioKey     INT            NULL,
    ClienteKey        INT            NOT NULL,
    EmpleadoKey       INT            NOT NULL,
    TransportistaKey  INT            NOT NULL,
    Cantidad          INT            NOT NULL,
    PrecioUnitario    DECIMAL(10,2)  NOT NULL,
    Descuento         DECIMAL(4,2)   NOT NULL,  -- normalizado desde el real impreciso del origen
    MontoBruto        DECIMAL(12,2)  NOT NULL,  -- Cantidad * PrecioUnitario
    MontoDescuento    DECIMAL(12,2)  NOT NULL,  -- MontoBruto * Descuento
    MontoNeto         DECIMAL(12,2)  NOT NULL,  -- MontoBruto - MontoDescuento (precalculado)
    DiasDespacho      INT            NULL,      -- FechaEnvio - FechaOrden; NULL si no se ha despachado
    CONSTRAINT PK_Fact_Detalle_Venta PRIMARY KEY (OrdenID, ProductoKey),
    CONSTRAINT FK_Fact_Cliente        FOREIGN KEY (ClienteKey)       REFERENCES dbo.Dim_Cliente (ClienteKey),
    CONSTRAINT FK_Fact_Producto       FOREIGN KEY (ProductoKey)      REFERENCES dbo.Dim_Producto (ProductoKey),
    CONSTRAINT FK_Fact_Empleado       FOREIGN KEY (EmpleadoKey)      REFERENCES dbo.Dim_Empleado (EmpleadoKey),
    CONSTRAINT FK_Fact_Transportista  FOREIGN KEY (TransportistaKey) REFERENCES dbo.Dim_Transportista (TransportistaKey),
    CONSTRAINT FK_Fact_FechaOrden     FOREIGN KEY (FechaOrdenKey)    REFERENCES dbo.Dim_Tiempo (FechaKey),
    CONSTRAINT FK_Fact_FechaEnvio     FOREIGN KEY (FechaEnvioKey)    REFERENCES dbo.Dim_Tiempo (FechaKey)
);
GO

-- Indices sobre las foraneas para los joins con las dimensiones
CREATE INDEX IX_Fact_FechaOrden    ON dbo.Fact_Detalle_Venta (FechaOrdenKey);
CREATE INDEX IX_Fact_FechaEnvio    ON dbo.Fact_Detalle_Venta (FechaEnvioKey);
CREATE INDEX IX_Fact_Cliente       ON dbo.Fact_Detalle_Venta (ClienteKey);
CREATE INDEX IX_Fact_Empleado      ON dbo.Fact_Detalle_Venta (EmpleadoKey);
CREATE INDEX IX_Fact_Transportista ON dbo.Fact_Detalle_Venta (TransportistaKey);
GO
