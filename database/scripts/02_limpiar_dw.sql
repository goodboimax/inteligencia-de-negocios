-- 02_limpiar_dw.sql
-- Kent Foods - vacia KentFoodsDW antes de cada carga (lo mismo hace la
-- primera tarea del Maestro.dtsx). Primero el hecho por las FK; no se
-- puede usar TRUNCATE en tablas con FK. Dim_Tiempo la limpia su procedimiento.

USE KentFoodsDW;
GO

DELETE FROM dbo.Fact_Detalle_Venta;
DELETE FROM dbo.Dim_Cliente;
DELETE FROM dbo.Dim_Producto;
DELETE FROM dbo.Dim_Empleado;
DELETE FROM dbo.Dim_Transportista;

-- reinicia los IDENTITY para que las claves partan en 1
-- (solo si la tabla ya tuvo filas, si no la primera quedaria en 0)
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
