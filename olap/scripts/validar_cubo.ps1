# Valida el cubo SSAS KentFoodsCubo comparando consultas MDX contra SQL en KentFoodsDW.
# Uso: powershell -ExecutionPolicy Bypass -File olap\scripts\validar_cubo.ps1
param(
    [string]$Servidor = 'localhost',
    [string]$BaseDW   = 'KentFoodsDW',
    [string]$BaseCubo = 'KentFoodsCubo',
    [string]$Cubo     = 'Kent Foods Ventas'
)
$ErrorActionPreference = 'Stop'

# ---------- Cargar AdomdClient de forma portable ----------
function Cargar-Adomd {
    $gac = Get-ChildItem -Path 'C:\Windows\Microsoft.NET\assembly\GAC_MSIL\Microsoft.AnalysisServices.AdomdClient' -Recurse -Filter 'Microsoft.AnalysisServices.AdomdClient.dll' -ErrorAction SilentlyContinue |
           Sort-Object FullName -Descending | Select-Object -First 1
    if ($gac) { Add-Type -Path $gac.FullName; return $gac.FullName }

    $rutas = @(
        'C:\Program Files\Microsoft.NET\ADOMD.NET\160\Microsoft.AnalysisServices.AdomdClient.dll',
        'C:\Program Files\Microsoft.NET\ADOMD.NET\150\Microsoft.AnalysisServices.AdomdClient.dll',
        'C:\Program Files\Microsoft.NET\ADOMD.NET\140\Microsoft.AnalysisServices.AdomdClient.dll',
        'C:\Program Files\Microsoft.NET\ADOMD.NET\130\Microsoft.AnalysisServices.AdomdClient.dll',
        'C:\Program Files (x86)\Microsoft.NET\ADOMD.NET\150\Microsoft.AnalysisServices.AdomdClient.dll',
        'C:\Program Files (x86)\Microsoft.NET\ADOMD.NET\130\Microsoft.AnalysisServices.AdomdClient.dll'
    )
    foreach ($r in $rutas) {
        if (Test-Path $r) { Add-Type -Path $r; return $r }
    }
    throw 'No se encontro Microsoft.AnalysisServices.AdomdClient.dll.'
}

Add-Type -AssemblyName System.Data
$adomdPath = Cargar-Adomd

$sqlCn = New-Object System.Data.SqlClient.SqlConnection "Server=$Servidor;Database=$BaseDW;Integrated Security=true;TrustServerCertificate=true"
$sqlCn.Open()

$mdxCn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection "Data Source=$Servidor;Catalog=$BaseCubo"
$mdxCn.Open()

# ---------- Helpers ----------
function Query-Sql($sql) {
    $cmd = $sqlCn.CreateCommand()
    $cmd.CommandText = $sql
    $dt = New-Object System.Data.DataTable
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    [void]$da.Fill($dt)
    return ,$dt
}

function Query-Mdx($mdx) {
    $cmd = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdCommand $mdx, $mdxCn
    return $cmd.ExecuteCellSet()
}

$script:controles = New-Object System.Collections.Generic.List[object]
$script:orden = 0

function Agregar-Control([string]$nombre, $esperado, $obtenido, [double]$tolerancia = 0.01) {
    $script:orden++
    $ok = $false
    if ($null -eq $esperado -and $null -eq $obtenido) {
        $ok = $true
    } elseif ($esperado -is [string] -or $obtenido -is [string]) {
        $ok = ([string]$esperado -eq [string]$obtenido)
    } elseif ($null -ne $esperado -and $null -ne $obtenido) {
        $ok = ([Math]::Abs([double]$esperado - [double]$obtenido) -le $tolerancia)
    }
    $fmtEsp = if ($null -eq $esperado) { 'NULL' } elseif ($esperado -is [double] -or $esperado -is [decimal]) { '{0:N2}' -f [double]$esperado } else { [string]$esperado }
    $fmtObt = if ($null -eq $obtenido) { 'NULL' } elseif ($obtenido -is [double] -or $obtenido -is [decimal]) { '{0:N2}' -f [double]$obtenido } else { [string]$obtenido }
    $script:controles.Add([pscustomobject]@{
        Orden     = $script:orden
        Control   = $nombre
        Esperado  = $fmtEsp
        Obtenido  = $fmtObt
        Resultado = if ($ok) { 'OK' } else { 'REVISAR' }
    })
}

try {
    # =====================================================================
    # 1) KPI GLOBALES (SQL KentFoodsDW vs MDX KentFoodsCubo)
    # =====================================================================
    $sqlGlobal = (Query-Sql @"
SELECT
    CAST(SUM(MontoNeto) AS FLOAT)                                                AS VentasNetas,
    CAST(SUM(MontoBruto) AS FLOAT)                                               AS MontoBruto,
    CAST(SUM(MontoDescuento) AS FLOAT)                                           AS MontoDescuento,
    CAST(SUM(Cantidad) AS FLOAT)                                                 AS Cantidad,
    CAST(COUNT(*) AS FLOAT)                                                      AS Lineas,
    CAST(COUNT(DISTINCT OrdenID) AS FLOAT)                                       AS Ordenes,
    CAST(SUM(MontoNeto) / COUNT(DISTINCT OrdenID) AS FLOAT)                      AS TicketPromedio,
    CAST(100.0 * SUM(MontoDescuento) / SUM(MontoBruto) AS FLOAT)                 AS PctDescuento,
    CAST(SUM(MontoDescuento) / COUNT(DISTINCT OrdenID) AS FLOAT)                 AS DescuentoPromedioOrden,
    CAST(COUNT(DISTINCT CASE WHEN FechaEnvioKey IS NULL THEN OrdenID END) AS FLOAT) AS OrdenesSinEnvio,
    CAST(SUM(CASE WHEN FechaEnvioKey IS NULL THEN 1 ELSE 0 END) AS FLOAT)        AS LineasSinEnvio
FROM dbo.Fact_Detalle_Venta
"@).Rows[0]

    $sqlDesp = (Query-Sql @"
SELECT
    CAST(COUNT(DiasDespacho) AS FLOAT)              AS OrdenesDespachadas,
    CAST(AVG(CAST(DiasDespacho AS FLOAT)) AS FLOAT) AS DiasPromedioDespacho
FROM (SELECT OrdenID, MIN(DiasDespacho) AS DiasDespacho FROM dbo.Fact_Detalle_Venta GROUP BY OrdenID) o
"@).Rows[0]

    $csGlobal = Query-Mdx @"
SELECT {
    [Measures].[Monto Neto],
    [Measures].[Monto Bruto],
    [Measures].[Monto Descuento],
    [Measures].[Cantidad],
    [Measures].[Lineas Detalle],
    [Measures].[Ordenes],
    [Measures].[Ticket Promedio],
    [Measures].[Pct Descuento],
    [Measures].[Descuento Promedio Orden],
    [Measures].[Ordenes Despachadas],
    [Measures].[Dias Promedio Despacho]
} ON COLUMNS
FROM [$Cubo]
"@

    Agregar-Control 'KPI Global - Ventas Netas'            ([double]$sqlGlobal['VentasNetas'])            ([double]$csGlobal.Cells.Item(0).Value) 0.01
    Agregar-Control 'KPI Global - Monto Bruto'             ([double]$sqlGlobal['MontoBruto'])             ([double]$csGlobal.Cells.Item(1).Value) 0.01
    Agregar-Control 'KPI Global - Monto Descuento'         ([double]$sqlGlobal['MontoDescuento'])         ([double]$csGlobal.Cells.Item(2).Value) 0.01
    Agregar-Control 'KPI Global - Cantidad'                ([double]$sqlGlobal['Cantidad'])               ([double]$csGlobal.Cells.Item(3).Value) 0.0
    Agregar-Control 'KPI Global - Lineas Detalle'          ([double]$sqlGlobal['Lineas'])                 ([double]$csGlobal.Cells.Item(4).Value) 0.0
    Agregar-Control 'KPI Global - Ordenes'                 ([double]$sqlGlobal['Ordenes'])                ([double]$csGlobal.Cells.Item(5).Value) 0.0
    Agregar-Control 'KPI Global - Ticket Promedio'         ([double]$sqlGlobal['TicketPromedio'])         ([double]$csGlobal.Cells.Item(6).Value) 0.01
    Agregar-Control 'KPI Global - Pct Descuento (%)'       ([double]$sqlGlobal['PctDescuento'])           ([double]$csGlobal.Cells.Item(7).Value * 100.0) 0.01
    Agregar-Control 'KPI Global - Descuento Promedio Orden' ([double]$sqlGlobal['DescuentoPromedioOrden']) ([double]$csGlobal.Cells.Item(8).Value) 0.01
    Agregar-Control 'KPI Global - Ordenes Despachadas'     ([double]$sqlDesp['OrdenesDespachadas'])       ([double]$csGlobal.Cells.Item(9).Value) 0.0
    Agregar-Control 'KPI Global - Dias Promedio Despacho'  ([double]$sqlDesp['DiasPromedioDespacho'])     ([double]$csGlobal.Cells.Item(10).Value) 0.01

    $csUnk = Query-Mdx @"
SELECT {[Measures].[Ordenes], [Measures].[Lineas Detalle]} ON COLUMNS,
       {[Fecha Envio].[Fecha].UNKNOWNMEMBER} ON ROWS
FROM [$Cubo]
"@
    Agregar-Control 'Fecha Envio Sin dato - Ordenes' ([double]$sqlGlobal['OrdenesSinEnvio']) ([double]$csUnk.Cells.Item(0, 0).Value) 0.0
    Agregar-Control 'Fecha Envio Sin dato - Lineas'  ([double]$sqlGlobal['LineasSinEnvio'])  ([double]$csUnk.Cells.Item(1, 0).Value) 0.0

    # =====================================================================
    # 2) INTEGRIDAD DEL CUBO: ORDEN CRONOLOGICO Y DIMENSIONES NO RELACIONADAS
    # =====================================================================
    $dtMes = Query-Sql @"
SELECT t.AnioMes, t.NombreMes + ' ' + CAST(t.Anio AS VARCHAR(4)) AS Etiqueta, CAST(SUM(f.MontoNeto) AS FLOAT) AS MontoNeto
FROM dbo.Fact_Detalle_Venta f
JOIN dbo.Dim_Tiempo t ON f.FechaOrdenKey = t.FechaKey
GROUP BY t.AnioMes, t.NombreMes, t.Anio
ORDER BY t.AnioMes
"@
    $csMes = Query-Mdx @"
SELECT {[Measures].[Monto Neto]} ON COLUMNS,
       NON EMPTY [Fecha Orden].[Mes].[Mes].MEMBERS ON ROWS
FROM [$Cubo]
"@
    $mesSqlLabels = @($dtMes.Rows | ForEach-Object { [string]$_['Etiqueta'] })
    $mesMdxLabels = @($csMes.Axes[1].Positions | ForEach-Object { $_.Members[0].Caption })
    Agregar-Control 'Tiempo - Cantidad de meses con ventas' $mesSqlLabels.Count $mesMdxLabels.Count 0.0
    $mesOrdenOk = (($mesSqlLabels -join ',') -eq ($mesMdxLabels -join ','))
    $mesEspResumen = "$($mesSqlLabels[0]) .. $($mesSqlLabels[-1])"
    $mesObtResumen = if ($mesOrdenOk) { "$($mesMdxLabels[0]) .. $($mesMdxLabels[-1])" } else { "DESORDENADO ($($mesMdxLabels[0])..)" }
    Agregar-Control 'Tiempo - Orden cronologico de Mes (Jul 2016..May 2018)' $mesEspResumen $mesObtResumen

    $maxDiffMes = 0.0
    for ($i = 0; $i -lt [Math]::Min($dtMes.Rows.Count, $csMes.Axes[1].Positions.Count); $i++) {
        $d = [Math]::Abs([double]$dtMes.Rows[$i]['MontoNeto'] - [double]$csMes.Cells.Item(0, $i).Value)
        if ($d -gt $maxDiffMes) { $maxDiffMes = $d }
    }
    Agregar-Control 'Tiempo - Ventas por Anio/Mes (max diff)' 0.0 $maxDiffMes 0.01

    $dtTrim = Query-Sql @"
SELECT t.AnioTrimestre, 'T' + CAST(t.Trimestre AS VARCHAR(1)) + ' ' + CAST(t.Anio AS VARCHAR(4)) AS Etiqueta, CAST(SUM(f.MontoNeto) AS FLOAT) AS MontoNeto
FROM dbo.Fact_Detalle_Venta f
JOIN dbo.Dim_Tiempo t ON f.FechaOrdenKey = t.FechaKey
GROUP BY t.AnioTrimestre, t.Trimestre, t.Anio
ORDER BY t.AnioTrimestre
"@
    $csTrim = Query-Mdx @"
SELECT {[Measures].[Monto Neto]} ON COLUMNS,
       NON EMPTY [Fecha Orden].[Anio-Trimestre-Mes-Dia].[Trimestre].MEMBERS ON ROWS
FROM [$Cubo]
"@
    $trimSqlLabels = @($dtTrim.Rows | ForEach-Object { [string]$_['Etiqueta'] })
    $trimMdxLabels = @($csTrim.Axes[1].Positions | ForEach-Object { $_.Members[0].Caption })
    $trimOrdenOk = (($trimSqlLabels -join ',') -eq ($trimMdxLabels -join ','))
    $trimEspResumen = "$($trimSqlLabels[0]) .. $($trimSqlLabels[-1]) ($($trimSqlLabels.Count))"
    $trimObtResumen = if ($trimOrdenOk) { "$($trimMdxLabels[0]) .. $($trimMdxLabels[-1]) ($($trimMdxLabels.Count))" } else { "DESORDENADO ($($trimMdxLabels[0])..)" }
    Agregar-Control 'Tiempo - Orden cronologico de Trimestre' $trimEspResumen $trimObtResumen

    $csUnrel = Query-Mdx @"
SELECT {[Measures].[Ordenes Despachadas], [Measures].[Dias Promedio Despacho]} ON COLUMNS,
       {[Producto].[Categoria].&[Beverages]} ON ROWS
FROM [$Cubo]
"@
    Agregar-Control 'Despachos x Producto (IgnoreUnrelated=False) - Ordenes Despachadas' $null $csUnrel.Cells.Item(0, 0).Value
    Agregar-Control 'Despachos x Producto (IgnoreUnrelated=False) - Dias Promedio'       $null $csUnrel.Cells.Item(1, 0).Value

    # =====================================================================
    # 3) DRILLDOWN: CATEGORIA (Producto)
    # =====================================================================
    $dtCat = Query-Sql @"
SELECT p.Categoria, CAST(SUM(f.MontoNeto) AS FLOAT) AS MontoNeto
FROM dbo.Fact_Detalle_Venta f
JOIN dbo.Dim_Producto p ON f.ProductoKey = p.ProductoKey
GROUP BY p.Categoria
ORDER BY p.Categoria
"@
    $csCat = Query-Mdx @"
SELECT {[Measures].[Monto Neto]} ON COLUMNS,
       NON EMPTY [Producto].[Categoria-Producto].[Categoria].MEMBERS ON ROWS
FROM [$Cubo]
"@
    $mdxCat = @{}
    for ($i = 0; $i -lt $csCat.Axes[1].Positions.Count; $i++) {
        $mdxCat[$csCat.Axes[1].Positions[$i].Members[0].Caption] = [double]$csCat.Cells.Item(0, $i).Value
    }
    $maxDiffCat = 0.0
    foreach ($r in $dtCat.Rows) {
        $k = [string]$r['Categoria']
        $v = if ($mdxCat.ContainsKey($k)) { $mdxCat[$k] } else { -1.0 }
        $d = [Math]::Abs([double]$r['MontoNeto'] - $v)
        if ($d -gt $maxDiffCat) { $maxDiffCat = $d }
    }
    Agregar-Control 'Producto - Beverages (lider)' 267868.16 $mdxCat['Beverages'] 0.01
    Agregar-Control 'Producto - Todas las categorias (8, max diff)' 0.0 $maxDiffCat 0.01

    # =====================================================================
    # 4) DRILLDOWN: REGION / EMPLEADO
    # =====================================================================
    $dtEmp = Query-Sql @"
SELECT e.Region, e.NombreEmpleado, CAST(SUM(f.MontoNeto) AS FLOAT) AS MontoNeto
FROM dbo.Fact_Detalle_Venta f
JOIN dbo.Dim_Empleado e ON f.EmpleadoKey = e.EmpleadoKey
GROUP BY e.Region, e.NombreEmpleado
ORDER BY e.Region, e.NombreEmpleado
"@
    $csEmp = Query-Mdx @"
SELECT {[Measures].[Monto Neto]} ON COLUMNS,
       NON EMPTY [Empleado].[Region-Empleado].[Nombre Empleado].MEMBERS ON ROWS
FROM [$Cubo]
"@
    $mdxEmp = @{}
    for ($i = 0; $i -lt $csEmp.Axes[1].Positions.Count; $i++) {
        $m = $csEmp.Axes[1].Positions[$i].Members[0]
        $mdxEmp["$($m.Parent.Caption)|$($m.Caption)"] = [double]$csEmp.Cells.Item(0, $i).Value
    }
    $maxDiffEmp = 0.0
    foreach ($r in $dtEmp.Rows) {
        $k = "$($r['Region'])|$($r['NombreEmpleado'])"
        $v = if ($mdxEmp.ContainsKey($k)) { $mdxEmp[$k] } else { -1.0 }
        $d = [Math]::Abs([double]$r['MontoNeto'] - $v)
        if ($d -gt $maxDiffEmp) { $maxDiffEmp = $d }
    }
    Agregar-Control 'Empleado - Margaret Peacock (max)' 232890.82 $mdxEmp['Eastern|Margaret Peacock'] 0.01
    Agregar-Control 'Empleado - Steven Buchanan (min)'   68792.25 $mdxEmp['Eastern|Steven Buchanan']  0.01
    Agregar-Control 'Empleado - Jerarquia Region-Empleado (9, max diff)' 0.0 $maxDiffEmp 0.01

    # =====================================================================
    # 5) DRILLDOWN: PAIS / CIUDAD (Cliente)
    # =====================================================================
    $dtGeo = Query-Sql @"
SELECT c.Pais, c.Ciudad, CAST(SUM(f.MontoNeto) AS FLOAT) AS MontoNeto
FROM dbo.Fact_Detalle_Venta f
JOIN dbo.Dim_Cliente c ON f.ClienteKey = c.ClienteKey
GROUP BY c.Pais, c.Ciudad
ORDER BY c.Pais, c.Ciudad
"@
    $csGeo = Query-Mdx @"
SELECT {[Measures].[Monto Neto]} ON COLUMNS,
       NON EMPTY [Cliente].[Pais-Ciudad-Empresa].[Ciudad].MEMBERS ON ROWS
FROM [$Cubo]
"@
    $mdxGeo = @{}
    for ($i = 0; $i -lt $csGeo.Axes[1].Positions.Count; $i++) {
        $m = $csGeo.Axes[1].Positions[$i].Members[0]
        $mdxGeo["$($m.Parent.Caption)|$($m.Caption)"] = [double]$csGeo.Cells.Item(0, $i).Value
    }
    $maxDiffGeo = 0.0
    foreach ($r in $dtGeo.Rows) {
        $k = "$($r['Pais'])|$($r['Ciudad'])"
        $v = if ($mdxGeo.ContainsKey($k)) { $mdxGeo[$k] } else { -1.0 }
        $d = [Math]::Abs([double]$r['MontoNeto'] - $v)
        if ($d -gt $maxDiffGeo) { $maxDiffGeo = $d }
    }
    Agregar-Control 'Cliente - Ciudades con ventas (conteo)' $dtGeo.Rows.Count $mdxGeo.Count 0.0
    Agregar-Control 'Cliente - Jerarquia Pais-Ciudad (max diff)' 0.0 $maxDiffGeo 0.01

    # =====================================================================
    # 6) DRILLDOWN: TRANSPORTISTA (Ventas + Dias Promedio Despacho)
    # =====================================================================
    $dtShip = Query-Sql @"
SELECT
    x.Transportista,
    CAST(SUM(f.MontoNeto) AS FLOAT) AS MontoNeto,
    CAST((SELECT COUNT(o.DiasDespacho) FROM (SELECT OrdenID, MIN(DiasDespacho) DiasDespacho, MIN(TransportistaKey) TK FROM dbo.Fact_Detalle_Venta GROUP BY OrdenID) o WHERE o.TK = x.TransportistaKey) AS FLOAT) AS OrdDesp,
    CAST((SELECT AVG(CAST(o.DiasDespacho AS FLOAT)) FROM (SELECT OrdenID, MIN(DiasDespacho) DiasDespacho, MIN(TransportistaKey) TK FROM dbo.Fact_Detalle_Venta GROUP BY OrdenID) o WHERE o.TK = x.TransportistaKey) AS FLOAT) AS PromDias
FROM dbo.Fact_Detalle_Venta f
JOIN dbo.Dim_Transportista x ON f.TransportistaKey = x.TransportistaKey
GROUP BY x.TransportistaKey, x.Transportista
ORDER BY x.Transportista
"@
    $csShip = Query-Mdx @"
SELECT {[Measures].[Monto Neto], [Measures].[Ordenes Despachadas], [Measures].[Dias Promedio Despacho]} ON COLUMNS,
       NON EMPTY [Transportista].[Nombre Transportista].[Nombre Transportista].MEMBERS ON ROWS
FROM [$Cubo]
"@
    $mdxShip = @{}
    for ($i = 0; $i -lt $csShip.Axes[1].Positions.Count; $i++) {
        $cap = $csShip.Axes[1].Positions[$i].Members[0].Caption
        $mdxShip[$cap] = @{
            Neto     = [double]$csShip.Cells.Item(0, $i).Value
            OrdDesp  = [double]$csShip.Cells.Item(1, $i).Value
            PromDias = [double]$csShip.Cells.Item(2, $i).Value
        }
    }
    foreach ($r in $dtShip.Rows) {
        $t = [string]$r['Transportista']
        Agregar-Control "Transportista - $t (Monto Neto)"          ([double]$r['MontoNeto']) $mdxShip[$t].Neto     0.01
        Agregar-Control "Transportista - $t (Ordenes Despachadas)" ([double]$r['OrdDesp'])   $mdxShip[$t].OrdDesp  0.0
        Agregar-Control "Transportista - $t (Dias Promedio)"       ([double]$r['PromDias'])  $mdxShip[$t].PromDias 0.01
    }

    # ---------- Reporte ----------
    Write-Host "ADOMD.NET: $adomdPath"
    Write-Host "Validacion DW ($BaseDW) vs Cubo ($BaseCubo / [$Cubo]):"
    $script:controles | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

    $fallos = @($script:controles | Where-Object { $_.Resultado -ne 'OK' })
    if ($fallos.Count -gt 0) {
        Write-Host "RESULTADO: $($fallos.Count) control(es) con diferencias." -ForegroundColor Red
        exit 1
    }
    Write-Host "RESULTADO: Todos los $($script:controles.Count) controles OK." -ForegroundColor Green
    exit 0
}
finally {
    if ($mdxCn.State -eq 'Open') { $mdxCn.Close() }
    if ($sqlCn.State -eq 'Open') { $sqlCn.Close() }
}
