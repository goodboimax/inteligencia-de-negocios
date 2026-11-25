# Crea y procesa el cubo KentFoodsCubo (SSAS Multidimensional) sobre KentFoodsDW.
# Uso: powershell -ExecutionPolicy Bypass -File olap\scripts\crear_cubo.ps1
param(
    [string]$Servidor = 'localhost',
    [string]$BaseDW   = 'KentFoodsDW',
    [string]$NombreDb = 'KentFoodsCubo'
)
$ErrorActionPreference = 'Stop'

# ---------- Cargar AMO de forma portable (GAC / SDK 160..110) ----------
function Cargar-AMO {
    $gacBase = 'C:\Windows\Microsoft.NET\assembly\GAC_MSIL'
    $gacCore = Get-ChildItem -Path (Join-Path $gacBase 'Microsoft.AnalysisServices.Core') -Recurse -Filter 'Microsoft.AnalysisServices.Core.dll' -ErrorAction SilentlyContinue |
               Sort-Object FullName -Descending | Select-Object -First 1
    $gacAmo  = Get-ChildItem -Path (Join-Path $gacBase 'Microsoft.AnalysisServices') -Recurse -Filter 'Microsoft.AnalysisServices.dll' -ErrorAction SilentlyContinue |
               Sort-Object FullName -Descending | Select-Object -First 1

    if ($gacAmo) {
        if ($gacCore) { Add-Type -Path $gacCore.FullName }
        Add-Type -Path $gacAmo.FullName
        return $gacAmo.FullName
    }

    $rutasSdk = @(
        'C:\Program Files\Microsoft SQL Server\160\SDK\Assemblies',
        'C:\Program Files\Microsoft SQL Server\150\SDK\Assemblies',
        'C:\Program Files\Microsoft SQL Server\140\SDK\Assemblies',
        'C:\Program Files\Microsoft SQL Server\130\SDK\Assemblies',
        'C:\Program Files (x86)\Microsoft SQL Server\160\SDK\Assemblies',
        'C:\Program Files (x86)\Microsoft SQL Server\150\SDK\Assemblies',
        'C:\Program Files (x86)\Microsoft SQL Server\140\SDK\Assemblies',
        'C:\Program Files (x86)\Microsoft SQL Server\130\SDK\Assemblies',
        'C:\Program Files (x86)\Microsoft SQL Server\120\SDK\Assemblies',
        'C:\Program Files (x86)\Microsoft SQL Server\110\SDK\Assemblies'
    )
    foreach ($dir in $rutasSdk) {
        $amo = Join-Path $dir 'Microsoft.AnalysisServices.DLL'
        if (Test-Path $amo) {
            $core = Join-Path $dir 'Microsoft.AnalysisServices.Core.DLL'
            if (Test-Path $core) { Add-Type -Path $core }
            Add-Type -Path $amo
            return $amo
        }
    }
    throw 'No se encontro Microsoft.AnalysisServices.DLL en el GAC ni en SQL Server SDK (110-160).'
}

function Resolver-ProveedorOleDb {
    $enum = New-Object System.Data.OleDb.OleDbEnumerator
    $provs = @($enum.GetElements() | Select-Object -ExpandProperty SOURCES_NAME)
    if ($provs -contains 'MSOLEDBSQL')   { return 'Provider=MSOLEDBSQL' }
    if ($provs -contains 'SQLNCLI11')    { return 'Provider=SQLNCLI11.1' }
    if ($provs -contains 'MSOLEDBSQL19') { return 'Provider=MSOLEDBSQL19;Use Encryption for Data=Optional' }
    if ($provs -contains 'SQLOLEDB')     { return 'Provider=SQLOLEDB' }
    throw 'No se encontro un proveedor OLE DB compatible para SQL Server (MSOLEDBSQL, SQLNCLI11, MSOLEDBSQL19 o SQLOLEDB).'
}

Add-Type -AssemblyName System.Data
$amoPath  = Cargar-AMO
$provStr  = Resolver-ProveedorOleDb
$AS = 'Microsoft.AnalysisServices'
$T  = [System.Data.OleDb.OleDbType]
$tInt = $T::Integer; $tStr = $T::WChar; $tDbl = $T::Double

function DI($tabla, $col, $tipo) { New-Object "$AS.DataItem" -ArgumentList $tabla, $col, $tipo }

# ---------- Conexion y base ----------
$srv = New-Object "$AS.Server"
$srv.Connect($Servidor)
if ($srv.Databases.ContainsName($NombreDb)) { $srv.Databases[$NombreDb].Drop() }
$db = New-Object "$AS.Database"
$db.Name = $NombreDb; $db.ID = $NombreDb

# ---------- Data source ----------
$ds = New-Object "$AS.RelationalDataSource"
$ds.Name = 'KentFoodsDW'; $ds.ID = 'KentFoodsDW'
$ds.ConnectionString = "$provStr;Data Source=$Servidor;Integrated Security=SSPI;Initial Catalog=$BaseDW"
$ds.ImpersonationInfo = New-Object "$AS.ImpersonationInfo"
$ds.ImpersonationInfo.ImpersonationMode = [Microsoft.AnalysisServices.ImpersonationMode]::ImpersonateServiceAccount
$db.DataSources.Add($ds) | Out-Null

# ---------- Data source view ----------
$sqlCn = New-Object System.Data.SqlClient.SqlConnection "Server=$Servidor;Database=$BaseDW;Integrated Security=true;TrustServerCertificate=true"
$set = New-Object System.Data.DataSet
function AgregarTabla($nombre, $consulta, $tipo, $queryDef) {
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $consulta, $sqlCn
    $tbl = $da.FillSchema($set, [System.Data.SchemaType]::Source, $nombre)[0]
    $tbl.ExtendedProperties['TableType']    = $tipo
    $tbl.ExtendedProperties['FriendlyName'] = $nombre
    $tbl.ExtendedProperties['DbTableName']  = $nombre
    if ($tipo -eq 'Table') { $tbl.ExtendedProperties['DbSchemaName'] = 'dbo' }
    else { $tbl.ExtendedProperties['QueryDefinition'] = $queryDef }
    foreach ($c in $tbl.Columns) {
        $c.ExtendedProperties['DbColumnName'] = $c.ColumnName
        $c.ExtendedProperties['FriendlyName'] = $c.ColumnName
    }
}
function AgregarColumnaCalculada($tabla, $nombre, $tipoClr, $exprSql) {
    $col = New-Object System.Data.DataColumn $nombre, $tipoClr
    $col.ReadOnly = $true
    $col.ExtendedProperties['DbColumnName'] = $nombre
    $col.ExtendedProperties['FriendlyName'] = $nombre
    $col.ExtendedProperties['ComputedColumnExpression'] = $exprSql
    $col.ExtendedProperties['IsLogical'] = 'True'
    $tabla.Columns.Add($col)
}

AgregarTabla 'Dim_Tiempo' 'SELECT * FROM dbo.Dim_Tiempo' 'Table' $null
$tblTiempo = $set.Tables['Dim_Tiempo']
# Calculos nombrados en la DSV para etiquetas legibles y orden cronologico sin alterar el DDL del DW
AgregarColumnaCalculada $tblTiempo 'NombreTrimestre' ([string]) "('T' + CAST(Trimestre AS VARCHAR(1)) + ' ' + CAST(Anio AS VARCHAR(4)))"
AgregarColumnaCalculada $tblTiempo 'NombreMesAnio'   ([string]) "(NombreMes + ' ' + CAST(Anio AS VARCHAR(4)))"
AgregarColumnaCalculada $tblTiempo 'DiaSemanaNum'    ([int])    "(CASE NombreDiaSemana WHEN 'Lunes' THEN 1 WHEN 'Martes' THEN 2 WHEN 'Miercoles' THEN 3 WHEN 'Jueves' THEN 4 WHEN 'Viernes' THEN 5 WHEN 'Sabado' THEN 6 ELSE 7 END)"

foreach ($t in 'Dim_Cliente','Dim_Producto','Dim_Empleado','Dim_Transportista','Fact_Detalle_Venta') {
    AgregarTabla $t "SELECT * FROM dbo.$t" 'Table' $null
}
# Una fila por orden, para promediar los dias de despacho por orden (grano de orden, sin Producto).
$qOrden = @"
SELECT OrdenID, MIN(FechaOrdenKey) AS FechaOrdenKey, MIN(FechaEnvioKey) AS FechaEnvioKey,
       MIN(ClienteKey) AS ClienteKey, MIN(EmpleadoKey) AS EmpleadoKey,
       MIN(TransportistaKey) AS TransportistaKey, MIN(DiasDespacho) AS DiasDespacho
FROM dbo.Fact_Detalle_Venta GROUP BY OrdenID
"@
AgregarTabla 'Fact_Orden' $qOrden 'View' $qOrden
$set.Tables['Fact_Orden'].PrimaryKey = @($set.Tables['Fact_Orden'].Columns['OrdenID'])
$sqlCn.Dispose()

# Relaciones en la DSV para que Visual Studio muestre las flechas del esquema estrella
function AgregarRelacionDsv($nombre, $tablaDim, $colDim, $tablaFact, $colFact, [bool]$logica = $false) {
    $rel = New-Object System.Data.DataRelation $nombre, $set.Tables[$tablaDim].Columns[$colDim], $set.Tables[$tablaFact].Columns[$colFact], $true
    if ($logica) { $rel.ExtendedProperties['IsLogical'] = 'True' }
    $set.Relations.Add($rel)
}
AgregarRelacionDsv 'FK_FactDetalle_FechaOrden'    'Dim_Tiempo'        'FechaKey'         'Fact_Detalle_Venta' 'FechaOrdenKey'
AgregarRelacionDsv 'FK_FactDetalle_FechaEnvio'    'Dim_Tiempo'        'FechaKey'         'Fact_Detalle_Venta' 'FechaEnvioKey'
AgregarRelacionDsv 'FK_FactDetalle_Cliente'       'Dim_Cliente'       'ClienteKey'       'Fact_Detalle_Venta' 'ClienteKey'
AgregarRelacionDsv 'FK_FactDetalle_Producto'      'Dim_Producto'      'ProductoKey'      'Fact_Detalle_Venta' 'ProductoKey'
AgregarRelacionDsv 'FK_FactDetalle_Empleado'      'Dim_Empleado'      'EmpleadoKey'      'Fact_Detalle_Venta' 'EmpleadoKey'
AgregarRelacionDsv 'FK_FactDetalle_Transportista' 'Dim_Transportista' 'TransportistaKey' 'Fact_Detalle_Venta' 'TransportistaKey'
AgregarRelacionDsv 'FK_FactOrden_FechaOrden'      'Dim_Tiempo'        'FechaKey'         'Fact_Orden'         'FechaOrdenKey'    $true
AgregarRelacionDsv 'FK_FactOrden_FechaEnvio'      'Dim_Tiempo'        'FechaKey'         'Fact_Orden'         'FechaEnvioKey'    $true
AgregarRelacionDsv 'FK_FactOrden_Cliente'         'Dim_Cliente'       'ClienteKey'       'Fact_Orden'         'ClienteKey'       $true
AgregarRelacionDsv 'FK_FactOrden_Empleado'        'Dim_Empleado'      'EmpleadoKey'      'Fact_Orden'         'EmpleadoKey'      $true
AgregarRelacionDsv 'FK_FactOrden_Transportista'   'Dim_Transportista' 'TransportistaKey' 'Fact_Orden'         'TransportistaKey' $true

$dsv = New-Object "$AS.DataSourceView"
$dsv.Name = 'KentFoodsDW'; $dsv.ID = 'KentFoodsDW'
$dsv.DataSourceID = $ds.ID
$dsv.Schema = $set
$db.DataSourceViews.Add($dsv) | Out-Null

# ---------- Dimensiones ----------
function NuevaDim($nombre, $tabla, $claveCol, $nombreClave, $colNombre, [bool]$conUnknown = $false, [string]$orderBy = 'Name') {
    $id = $nombre -replace ' ', ''
    $d = $db.Dimensions.Add($nombre, $id)
    $d.Source = New-Object "$AS.DataSourceViewBinding" -ArgumentList $dsv.ID
    if ($conUnknown) {
        $d.UnknownMember = [Microsoft.AnalysisServices.UnknownMemberBehavior]::Visible
        $d.UnknownMemberName = 'Sin dato'
    } else {
        $d.UnknownMember = [Microsoft.AnalysisServices.UnknownMemberBehavior]::None
    }
    $k = $d.Attributes.Add($nombreClave, "$($nombreClave -replace ' ','')")
    $k.Usage = [Microsoft.AnalysisServices.AttributeUsage]::Key
    $k.KeyColumns.Add((DI $tabla $claveCol $tInt)) | Out-Null
    $k.NameColumn = DI $tabla $colNombre $tStr
    $k.OrderBy = [Microsoft.AnalysisServices.OrderBy]::$orderBy
    return $d
}
function Atributo($dim, $nombre, $tabla, $colClave, $tipoClave, $colNombre, [string]$orderBy = 'Name') {
    $a = $dim.Attributes.Add($nombre, ($nombre -replace ' ', ''))
    $a.KeyColumns.Add((DI $tabla $colClave $tipoClave)) | Out-Null
    if ($colNombre) { $a.NameColumn = DI $tabla $colNombre $tStr }
    $a.OrderBy = [Microsoft.AnalysisServices.OrderBy]::$orderBy
    return $a
}
function Relacion($attr, $destino, [string]$tipoRel = 'Flexible') {
    $r = New-Object "$AS.AttributeRelationship" -ArgumentList $destino.ID
    $r.RelationshipType = [Microsoft.AnalysisServices.RelationshipType]::$tipoRel
    $attr.AttributeRelationships.Add($r) | Out-Null
}
function Jerarquia($dim, $nombre, $niveles) {
    $h = $dim.Hierarchies.Add($nombre, ($nombre -replace ' ', ''))
    foreach ($n in $niveles) {
        $lvl = $h.Levels.Add($n.Name)
        $lvl.SourceAttributeID = $n.ID
    }
}

# Tiempo (con UnknownMember Visible para las 21 ordenes sin FechaEnvioKey)
$dT = NuevaDim 'Tiempo' 'Dim_Tiempo' 'FechaKey' 'Fecha' 'Fecha' $true 'Key'
$dT.Type = [Microsoft.AnalysisServices.DimensionType]::Time
$tFecha = $dT.KeyAttribute
$tFecha.Type = [Microsoft.AnalysisServices.AttributeType]::Date
$tAnio   = Atributo $dT 'Anio'        'Dim_Tiempo' 'Anio'          $tInt 'Anio'            'Key'
$tAnio.Type = [Microsoft.AnalysisServices.AttributeType]::Years
$tTrim   = Atributo $dT 'Trimestre'   'Dim_Tiempo' 'AnioTrimestre' $tInt 'NombreTrimestre' 'Key'
$tTrim.Type = [Microsoft.AnalysisServices.AttributeType]::Quarters
$tMes    = Atributo $dT 'Mes'         'Dim_Tiempo' 'AnioMes'       $tInt 'NombreMesAnio'   'Key'
$tMes.Type = [Microsoft.AnalysisServices.AttributeType]::Months
$tMesAn  = Atributo $dT 'Mes del Anio' 'Dim_Tiempo' 'Mes'          $tInt 'NombreMes'       'Key'
$tDia    = Atributo $dT 'Dia Semana'  'Dim_Tiempo' 'DiaSemanaNum'  $tInt 'NombreDiaSemana' 'Key'
Relacion $tFecha $tMes    'Rigid'
Relacion $tMes   $tTrim   'Rigid'
Relacion $tTrim  $tAnio   'Rigid'
Relacion $tMes   $tMesAn  'Rigid'
Relacion $tFecha $tDia    'Rigid'
Jerarquia $dT 'Anio-Trimestre-Mes-Dia' @($tAnio, $tTrim, $tMes, $tFecha)

# Cliente (clave compuesta Pais+Ciudad para evitar colisiones entre paises + jerarquia natural)
$dC = NuevaDim 'Cliente' 'Dim_Cliente' 'ClienteKey' 'Empresa' 'Empresa' $false 'Name'
$cPais = Atributo $dC 'Pais' 'Dim_Cliente' 'Pais' $tStr $null 'Name'
$cCiudad = $dC.Attributes.Add('Ciudad', 'Ciudad')
$cCiudad.KeyColumns.Add((DI 'Dim_Cliente' 'Pais'   $tStr)) | Out-Null
$cCiudad.KeyColumns.Add((DI 'Dim_Cliente' 'Ciudad' $tStr)) | Out-Null
$cCiudad.NameColumn = DI 'Dim_Cliente' 'Ciudad' $tStr
$cCiudad.OrderBy = [Microsoft.AnalysisServices.OrderBy]::Name
Relacion $dC.KeyAttribute $cCiudad 'Flexible'
Relacion $cCiudad         $cPais   'Rigid'
Jerarquia $dC 'Pais-Ciudad-Empresa' @($cPais, $cCiudad, $dC.KeyAttribute)

# Producto (incluye Pais Proveedor y jerarquias naturales)
$dP = NuevaDim 'Producto' 'Dim_Producto' 'ProductoKey' 'Producto' 'Producto' $false 'Name'
$pCat      = Atributo $dP 'Categoria'      'Dim_Producto' 'Categoria'     $tStr $null 'Name'
$pProv     = Atributo $dP 'Proveedor'      'Dim_Producto' 'Proveedor'     $tStr $null 'Name'
$pPaisProv = Atributo $dP 'Pais Proveedor' 'Dim_Producto' 'PaisProveedor' $tStr $null 'Name'
Relacion $dP.KeyAttribute $pCat      'Flexible'
Relacion $dP.KeyAttribute $pProv     'Flexible'
Relacion $pProv           $pPaisProv 'Flexible'
Jerarquia $dP 'Categoria-Producto'             @($pCat, $dP.KeyAttribute)
Jerarquia $dP 'Pais Proveedor-Proveedor-Producto' @($pPaisProv, $pProv, $dP.KeyAttribute)

# Empleado (incluye Pais)
$dE = NuevaDim 'Empleado' 'Dim_Empleado' 'EmpleadoKey' 'Nombre Empleado' 'NombreEmpleado' $false 'Name'
$eReg  = Atributo $dE 'Region' 'Dim_Empleado' 'Region' $tStr $null 'Name'
$eCar  = Atributo $dE 'Cargo'  'Dim_Empleado' 'Cargo'  $tStr $null 'Name'
$ePais = Atributo $dE 'Pais'   'Dim_Empleado' 'Pais'   $tStr $null 'Name'
Relacion $dE.KeyAttribute $eReg  'Flexible'
Relacion $dE.KeyAttribute $eCar  'Flexible'
Relacion $dE.KeyAttribute $ePais 'Flexible'
Jerarquia $dE 'Region-Empleado' @($eReg, $dE.KeyAttribute)

# Transportista
$dX = NuevaDim 'Transportista' 'Dim_Transportista' 'TransportistaKey' 'Nombre Transportista' 'Transportista' $false 'Name'

# ---------- Cubo ----------
$cubo = $db.Cubes.Add('Kent Foods Ventas', 'KentFoodsVentas')
$cubo.Source = New-Object "$AS.DataSourceViewBinding" -ArgumentList $dsv.ID
$cubo.StorageMode = [Microsoft.AnalysisServices.StorageMode]::Molap

# Dimensiones del cubo (Tiempo se usa dos veces: fecha de orden y de envio)
function DimCubo($nombre, $dim) { $cubo.Dimensions.Add($dim.ID, $nombre, ($nombre -replace ' ', '')) | Out-Null }
DimCubo 'Fecha Orden'   $dT
DimCubo 'Fecha Envio'   $dT
DimCubo 'Cliente'       $dC
DimCubo 'Producto'      $dP
DimCubo 'Empleado'      $dE
DimCubo 'Transportista' $dX

function NuevoGrupo($nombre, $tabla, $relaciones, [bool]$ignoreUnrelated = $true) {
    $mg = $cubo.MeasureGroups.Add($nombre, ($nombre -replace ' ', ''))
    $mg.IgnoreUnrelatedDimensions = $ignoreUnrelated
    foreach ($r in $relaciones) {   # @(idDimCubo, atributoClave, columnaFact)
        $rel = New-Object "$AS.RegularMeasureGroupDimension" -ArgumentList $r[0]
        $att = New-Object "$AS.MeasureGroupAttribute" -ArgumentList $r[1]
        $att.Type = [Microsoft.AnalysisServices.MeasureGroupAttributeType]::Granularity
        $diKey = DI $tabla $r[2] $tInt
        if ($r[2] -eq 'FechaEnvioKey') {
            $diKey.NullProcessing = [Microsoft.AnalysisServices.NullProcessing]::UnknownMember
        }
        $att.KeyColumns.Add($diKey) | Out-Null
        $rel.Attributes.Add($att) | Out-Null
        $mg.Dimensions.Add($rel) | Out-Null
    }
    $mg.ProcessingMode = [Microsoft.AnalysisServices.ProcessingMode]::Regular
    $mg.StorageMode = [Microsoft.AnalysisServices.StorageMode]::Molap
    $ec = New-Object "$AS.ErrorConfiguration"
    $ec.KeyNotFound = [Microsoft.AnalysisServices.ErrorOption]::ReportAndStop
    $ec.NullKeyNotAllowed = [Microsoft.AnalysisServices.ErrorOption]::IgnoreError
    $ec.NullKeyConvertedToUnknown = [Microsoft.AnalysisServices.ErrorOption]::IgnoreError
    $mg.ErrorConfiguration = $ec
    $p = $mg.Partitions.Add($nombre, ($nombre -replace ' ', ''))
    if ($tabla -eq 'Fact_Orden') { $p.Source = New-Object "$AS.QueryBinding" -ArgumentList $ds.ID, $qOrden }
    else { $p.Source = New-Object "$AS.TableBinding" -ArgumentList $ds.ID, 'dbo', $tabla }
    $p.StorageMode = [Microsoft.AnalysisServices.StorageMode]::Molap
    return $mg
}
function Medida($mg, $nombre, $tabla, $col, $tipo, $agg, $fmt, [bool]$visible = $true) {
    $m = $mg.Measures.Add($nombre, ($nombre -replace ' ', ''))
    $m.AggregateFunction = [Microsoft.AnalysisServices.AggregationFunction]::$agg
    $m.Source = DI $tabla $col $tipo
    $m.Visible = $visible
    if ($fmt) { $m.FormatString = $fmt }
    return $m
}

# Grupo 1: una fila por linea de detalle
$rel = @(
    @('FechaOrden',    'Fecha',               'FechaOrdenKey'),
    @('FechaEnvio',    'Fecha',               'FechaEnvioKey'),
    @('Cliente',       'Empresa',             'ClienteKey'),
    @('Producto',      'Producto',            'ProductoKey'),
    @('Empleado',      'NombreEmpleado',      'EmpleadoKey'),
    @('Transportista', 'NombreTransportista', 'TransportistaKey')
)
$mgV = NuevoGrupo 'Ventas' 'Fact_Detalle_Venta' $rel $true
Medida $mgV 'Cantidad'        'Fact_Detalle_Venta' 'Cantidad'       $tInt 'Sum'   '#,##0'    | Out-Null
Medida $mgV 'Monto Bruto'     'Fact_Detalle_Venta' 'MontoBruto'     $tDbl 'Sum'   '#,##0.00' | Out-Null
Medida $mgV 'Monto Descuento' 'Fact_Detalle_Venta' 'MontoDescuento' $tDbl 'Sum'   '#,##0.00' | Out-Null
Medida $mgV 'Monto Neto'      'Fact_Detalle_Venta' 'MontoNeto'      $tDbl 'Sum'   '#,##0.00' | Out-Null
Medida $mgV 'Lineas Detalle'  'Fact_Detalle_Venta' 'OrdenID'        $tInt 'Count' '#,##0'    | Out-Null

# Grupo 2: ordenes distintas (sirve para ticket promedio por cualquier dimension)
$mgO = NuevoGrupo 'Ordenes' 'Fact_Detalle_Venta' $rel $true
Medida $mgO 'Ordenes' 'Fact_Detalle_Venta' 'OrdenID' $tInt 'DistinctCount' '#,##0' | Out-Null

# Grupo 3: una fila por orden, para los dias de despacho (sin Producto; IgnoreUnrelatedDimensions=false)
$relOrd = @($rel | Where-Object { $_[0] -ne 'Producto' })
$mgD = NuevoGrupo 'Despachos' 'Fact_Orden' $relOrd $false
Medida $mgD 'Dias Despacho Total' 'Fact_Orden' 'DiasDespacho' $tInt 'Sum'   '#,##0' $false | Out-Null
Medida $mgD 'Ordenes Despachadas' 'Fact_Orden' 'DiasDespacho' $tInt 'Count' '#,##0' $true  | Out-Null

# KPI como miembros calculados
$mdx = $cubo.MdxScripts.Add('MdxScript', 'MdxScript')
$cmds = @(
    'CALCULATE;',
    "CREATE MEMBER CURRENTCUBE.[Measures].[Ticket Promedio] AS IIF([Measures].[Ordenes]=0, NULL, [Measures].[Monto Neto]/[Measures].[Ordenes]), FORMAT_STRING='#,##0.00', ASSOCIATED_MEASURE_GROUP='Ventas', VISIBLE=1;",
    "CREATE MEMBER CURRENTCUBE.[Measures].[Pct Descuento] AS IIF([Measures].[Monto Bruto]=0, NULL, [Measures].[Monto Descuento]/[Measures].[Monto Bruto]), FORMAT_STRING='0.00%', ASSOCIATED_MEASURE_GROUP='Ventas', VISIBLE=1;",
    "CREATE MEMBER CURRENTCUBE.[Measures].[Descuento Promedio Orden] AS IIF([Measures].[Ordenes]=0, NULL, [Measures].[Monto Descuento]/[Measures].[Ordenes]), ASSOCIATED_MEASURE_GROUP='Ventas', FORMAT_STRING='#,##0.00', VISIBLE=1;",
    "CREATE MEMBER CURRENTCUBE.[Measures].[Dias Promedio Despacho] AS IIF([Measures].[Ordenes Despachadas]=0, NULL, [Measures].[Dias Despacho Total]/[Measures].[Ordenes Despachadas]), FORMAT_STRING='#,##0.00', ASSOCIATED_MEASURE_GROUP='Despachos', VISIBLE=1;"
)
foreach ($c in $cmds) {
    $cmd = New-Object "$AS.Command"
    $cmd.Text = $c
    $mdx.Commands.Add($cmd) | Out-Null
}

# ---------- Validar definicion antes de desplegar ----------
$srv.Databases.Add($db) | Out-Null
$valResults = New-Object "$AS.ValidationResultCollection"
$esValido = $db.Validate($valResults)
if ($valResults.Count -gt 0) {
    Write-Host "Avisos de validacion AMO ($($valResults.Count)):" -ForegroundColor Yellow
    foreach ($vr in $valResults) { Write-Host "  [$($vr.ResultType)] $($vr.Description)" -ForegroundColor Yellow }
}
if (-not $esValido) {
    $srv.Disconnect()
    throw 'La definicion del cubo no paso la validacion AMO.'
}

# ---------- Desplegar y procesar ----------
$db.Update([Microsoft.AnalysisServices.UpdateOptions]::ExpandFull)
$srv.Databases.Refresh()
$dbSrv = $srv.Databases[$NombreDb]
$dbSrv.Process([Microsoft.AnalysisServices.ProcessType]::ProcessFull)
$dbSrv.Refresh()

Write-Host "AMO cargado desde: $amoPath"
Write-Host "Proveedor OLE DB:  $provStr"
Write-Host "Cubo '$NombreDb' desplegado y procesado en $Servidor (State=$($dbSrv.State))."
foreach ($dim in $dbSrv.Dimensions) {
    if ($dim.State -ne [Microsoft.AnalysisServices.AnalysisState]::Processed) {
        throw "Dimension '$($dim.Name)' quedo en estado $($dim.State)."
    }
}
foreach ($c in $dbSrv.Cubes) {
    if ($c.State -ne [Microsoft.AnalysisServices.AnalysisState]::Processed) {
        throw "Cubo '$($c.Name)' quedo en estado $($c.State)."
    }
}
$srv.Disconnect()
