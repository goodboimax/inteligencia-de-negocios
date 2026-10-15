-- 03_validar_carga.sql
-- Certamen 2 - Kent Foods - revisa que el ETL haya cargado bien KentFoodsDW
--
-- Se corre despues del paquete maestro de SSIS. Cada fila del resultado es
-- un control: lo que se espera (sacado de consultar la base original
-- KentFoods) contra lo que quedo en el DW. Si todo esta bien, la columna
-- Resultado dice OK en todas las filas.

USE KentFoodsDW;
GO

WITH Controles AS (
    -- Conteo de filas por tabla
    SELECT 1 AS Orden, 'Filas Dim_Cliente' AS Control,
           CAST(91 AS DECIMAL(14,2)) AS Esperado,
           CAST((SELECT COUNT(*) FROM dbo.Dim_Cliente) AS DECIMAL(14,2)) AS Obtenido
    UNION ALL SELECT 2, 'Filas Dim_Producto', 77,
           (SELECT COUNT(*) FROM dbo.Dim_Producto)
    UNION ALL SELECT 3, 'Filas Dim_Empleado', 9,
           (SELECT COUNT(*) FROM dbo.Dim_Empleado)
    UNION ALL SELECT 4, 'Filas Dim_Transportista', 3,
           (SELECT COUNT(*) FROM dbo.Dim_Transportista)
    UNION ALL SELECT 5, 'Filas Dim_Tiempo (2016-2018)', 1096,
           (SELECT COUNT(*) FROM dbo.Dim_Tiempo)
    UNION ALL SELECT 6, 'Filas Fact_Detalle_Venta', 2155,
           (SELECT COUNT(*) FROM dbo.Fact_Detalle_Venta)

    -- Totales de negocio (tienen que cuadrar con los KPI del README)
    UNION ALL SELECT 7, 'Ordenes distintas', 830,
           (SELECT COUNT(DISTINCT OrdenID) FROM dbo.Fact_Detalle_Venta)
    UNION ALL SELECT 8, 'Unidades vendidas', 51317,
           (SELECT SUM(Cantidad) FROM dbo.Fact_Detalle_Venta)
    UNION ALL SELECT 9, 'Monto bruto', 1354458.59,
           (SELECT SUM(MontoBruto) FROM dbo.Fact_Detalle_Venta)
    UNION ALL SELECT 10, 'Monto descuento', 88665.83,
           (SELECT SUM(MontoDescuento) FROM dbo.Fact_Detalle_Venta)
    UNION ALL SELECT 11, 'Monto neto', 1265792.76,
           (SELECT SUM(MontoNeto) FROM dbo.Fact_Detalle_Venta)

    -- Ordenes sin despachar: FechaEnvioKey y DiasDespacho en NULL
    UNION ALL SELECT 12, 'Lineas sin despachar', 73,
           (SELECT COUNT(*) FROM dbo.Fact_Detalle_Venta WHERE FechaEnvioKey IS NULL)
    UNION ALL SELECT 13, 'Ordenes sin despachar', 21,
           (SELECT COUNT(DISTINCT OrdenID) FROM dbo.Fact_Detalle_Venta WHERE FechaEnvioKey IS NULL)
    UNION ALL SELECT 14, 'NULL inconsistente FechaEnvio/DiasDespacho', 0,
           (SELECT COUNT(*) FROM dbo.Fact_Detalle_Venta
            WHERE (FechaEnvioKey IS NULL AND DiasDespacho IS NOT NULL)
               OR (FechaEnvioKey IS NOT NULL AND DiasDespacho IS NULL))

    -- Calidad de datos
    UNION ALL SELECT 15, 'Montos mal calculados', 0,
           (SELECT COUNT(*) FROM dbo.Fact_Detalle_Venta
            WHERE MontoNeto <> MontoBruto - MontoDescuento
               OR MontoBruto <> Cantidad * PrecioUnitario)
    UNION ALL SELECT 16, 'DiasDespacho negativos', 0,
           (SELECT COUNT(*) FROM dbo.Fact_Detalle_Venta WHERE DiasDespacho < 0)
    UNION ALL SELECT 17, 'Descuentos fuera de 0-1', 0,
           (SELECT COUNT(*) FROM dbo.Fact_Detalle_Venta WHERE Descuento NOT BETWEEN 0 AND 1)
    UNION ALL SELECT 18, 'Regiones con espacios al final', 0,
           (SELECT COUNT(*) FROM dbo.Dim_Empleado WHERE DATALENGTH(Region) <> DATALENGTH(RTRIM(Region)))
    UNION ALL SELECT 19, 'Claves sustitutas que no parten en 1', 0,
           (SELECT COUNT(*) FROM (
                SELECT MIN(ClienteKey) AS m FROM dbo.Dim_Cliente
                UNION ALL SELECT MIN(ProductoKey) FROM dbo.Dim_Producto
                UNION ALL SELECT MIN(EmpleadoKey) FROM dbo.Dim_Empleado
                UNION ALL SELECT MIN(TransportistaKey) FROM dbo.Dim_Transportista) x
            WHERE m <> 1)
)
SELECT Orden, Control, Esperado, Obtenido,
       CASE WHEN Obtenido = Esperado THEN 'OK' ELSE 'REVISAR' END AS Resultado
FROM Controles
ORDER BY Orden;
GO

-- Las huerfanas no se revisan aca porque las FK del hecho no lo permiten:
-- si el Lookup de SSIS no encuentra una clave, la fila no entra y se nota
-- en el conteo de Fact_Detalle_Venta (control 6).

-- Vista rapida de los KPI, para mostrar en la presentacion
SELECT
    SUM(MontoNeto)                                        AS VentasNetas,
    SUM(MontoNeto) / COUNT(DISTINCT OrdenID)              AS TicketPromedio,
    100.0 * SUM(MontoDescuento) / SUM(MontoBruto)         AS PorcentajeDescuento
FROM dbo.Fact_Detalle_Venta;

-- Dias promedio de despacho: por orden, no por linea (si no, las ordenes
-- con mas productos pesarian mas en el promedio)
SELECT AVG(CAST(DiasDespacho AS DECIMAL(6,2))) AS DiasPromedioDespacho
FROM (SELECT DISTINCT OrdenID, DiasDespacho
      FROM dbo.Fact_Detalle_Venta
      WHERE DiasDespacho IS NOT NULL) o;
GO
