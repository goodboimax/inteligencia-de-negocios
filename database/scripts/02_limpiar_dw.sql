-- 02_limpiar_dw.sql
-- Certamen 2 - Kent Foods - deja KentFoodsDW vacio antes de cada carga
--
-- Es lo primero que ejecuta el paquete maestro de SSIS (tarea Execute SQL).
-- Se borra primero el hecho y despues las dimensiones, por las foraneas
-- (no se puede usar TRUNCATE en tablas referenciadas por una FK).
--
-- El RESEED vuelve los IDENTITY a 0, asi la proxima fila insertada queda
-- con clave 1. Sin esto, cada vez que se corre el ETL las claves sustitutas
-- seguirian creciendo (la segunda carga partiria en 92 para clientes, etc.)
-- y no se podrian comparar dos cargas.
-- Dim_Tiempo no se toca aca: la limpia el propio usp_CargarDimTiempo.

USE KentFoodsDW;
GO

DELETE FROM dbo.Fact_Detalle_Venta;
DELETE FROM dbo.Dim_Cliente;
DELETE FROM dbo.Dim_Producto;
DELETE FROM dbo.Dim_Empleado;
DELETE FROM dbo.Dim_Transportista;

-- Ojo: si la tabla recien se creo y nunca tuvo filas, RESEED 0 hace que la
-- primera fila quede con clave 0. Por eso solo se resetea si ya se uso
-- (last_value queda NULL mientras no se haya insertado nada).
DECLARE @t SYSNAME;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT QUOTENAME(OBJECT_SCHEMA_NAME(object_id)) + '.' + QUOTENAME(OBJECT_NAME(object_id))
    FROM sys.identity_columns
    WHERE object_id IN (OBJECT_ID('dbo.Dim_Cliente'), OBJECT_ID('dbo.Dim_Producto'),
                        OBJECT_ID('dbo.Dim_Empleado'), OBJECT_ID('dbo.Dim_Transportista'))
      AND last_value IS NOT NULL;
OPEN c;
FETCH NEXT FROM c INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    DBCC CHECKIDENT (@t, RESEED, 0) WITH NO_INFOMSGS;
    FETCH NEXT FROM c INTO @t;
END
CLOSE c;
DEALLOCATE c;
GO
