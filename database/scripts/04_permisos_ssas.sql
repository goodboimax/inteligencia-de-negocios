-- 04_permisos_ssas.sql
-- Kent Foods - otorga permisos de lectura en KentFoodsDW a la cuenta del
-- servicio de Analysis Services para poder procesar el cubo SSAS.

IF NOT EXISTS (
    SELECT 1
    FROM sys.server_principals
    WHERE name = N'NT Service\MSSQLServerOLAPService'
)
BEGIN
    CREATE LOGIN [NT Service\MSSQLServerOLAPService] FROM WINDOWS;
END
GO

USE KentFoodsDW;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_principals
    WHERE name = N'NT Service\MSSQLServerOLAPService'
)
BEGIN
    CREATE USER [NT Service\MSSQLServerOLAPService]
        FOR LOGIN [NT Service\MSSQLServerOLAPService];
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members drm
    JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
    JOIN sys.database_principals m ON drm.member_principal_id = m.principal_id
    WHERE r.name = N'db_datareader'
      AND m.name = N'NT Service\MSSQLServerOLAPService'
)
BEGIN
    ALTER ROLE db_datareader ADD MEMBER [NT Service\MSSQLServerOLAPService];
END
GO
