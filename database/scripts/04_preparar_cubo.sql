-- 04_preparar_cubo.sql
-- Kent Foods - deja KentFoodsDW listo para el cubo SSAS (Fase 2).
-- Se corre despues de 01 + ETL + 03. Se puede correr varias veces.

USE KentFoodsDW;
GO

-- 1) Etiquetas para la jerarquia de tiempo del cubo ("T1 2017", "Enero 2017", "15-01-2017").
--    Son columnas calculadas: no cambian el ETL ni hay que recargar.
IF COL_LENGTH('dbo.Dim_Tiempo', 'NombreTrimestre') IS NULL
    ALTER TABLE dbo.Dim_Tiempo
        ADD NombreTrimestre AS ('T' + CAST(Trimestre AS VARCHAR(1)) + ' ' + CAST(Anio AS VARCHAR(4)));
IF COL_LENGTH('dbo.Dim_Tiempo', 'NombreMesAnio') IS NULL
    ALTER TABLE dbo.Dim_Tiempo
        ADD NombreMesAnio AS (NombreMes + ' ' + CAST(Anio AS VARCHAR(4)));
IF COL_LENGTH('dbo.Dim_Tiempo', 'FechaTexto') IS NULL
    ALTER TABLE dbo.Dim_Tiempo
        ADD FechaTexto AS (CONVERT(VARCHAR(10), Fecha, 105));  -- dd-mm-aaaa
GO

-- 2) Vista del hecho para el cubo.
--    El KPI de dias de despacho es por orden, no por linea (ver 03_validar_carga.sql).
--    Cada linea lleva su parte de la orden: si la orden tiene n lineas,
--    PesoOrdenDespachada = 1/n y DiasDespachoPonderado = DiasDespacho/n.
--    Sumando ambas columnas se obtienen los dias y las ordenes despachadas,
--    y su cociente es el promedio por orden (8,5 en todo el periodo).
CREATE OR ALTER VIEW dbo.vw_Fact_Venta_Cubo AS
SELECT
    f.OrdenID, f.ProductoKey, f.FechaOrdenKey, f.FechaEnvioKey,
    f.ClienteKey, f.EmpleadoKey, f.TransportistaKey,
    f.Cantidad, f.PrecioUnitario, f.Descuento,
    f.MontoBruto, f.MontoDescuento, f.MontoNeto, f.DiasDespacho,
    CAST(f.DiasDespacho AS FLOAT) / COUNT(*) OVER (PARTITION BY f.OrdenID) AS DiasDespachoPonderado,
    CASE WHEN f.DiasDespacho IS NULL THEN NULL
         ELSE CAST(1 AS FLOAT) / COUNT(*) OVER (PARTITION BY f.OrdenID) END AS PesoOrdenDespachada
FROM dbo.Fact_Detalle_Venta f;
GO

-- 3) Permiso de lectura para la cuenta del servicio de Analysis Services,
--    que es la que lee el DW al procesar el cubo.
--    Instancia por defecto: NT Service\MSSQLServerOLAPService.
--    Si SSAS es una instancia con nombre, cambiar por NT Service\MSOLAP$NOMBRE.
IF SUSER_ID('NT Service\MSSQLServerOLAPService') IS NULL
    CREATE LOGIN [NT Service\MSSQLServerOLAPService] FROM WINDOWS;
GO
IF USER_ID('NT Service\MSSQLServerOLAPService') IS NULL
    CREATE USER [NT Service\MSSQLServerOLAPService] FOR LOGIN [NT Service\MSSQLServerOLAPService];
ALTER ROLE db_datareader ADD MEMBER [NT Service\MSSQLServerOLAPService];
GO

-- Control: debe dar 830 ordenes, 809 despachadas y 8,5 dias promedio
SELECT
    COUNT(DISTINCT OrdenID)                               AS Ordenes,
    ROUND(SUM(PesoOrdenDespachada), 0)                    AS OrdenesDespachadas,
    SUM(DiasDespachoPonderado) / SUM(PesoOrdenDespachada) AS DiasPromedioDespacho
FROM dbo.vw_Fact_Venta_Cubo;
GO
