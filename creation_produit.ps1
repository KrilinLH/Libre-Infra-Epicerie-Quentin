param(
    [Parameter(Mandatory=$true)]
    [string]$PayloadJson
)

# --- 1. CONFIGURATION WOOCOMMERCE API ---
$WooUrl = "http://192.168.17.131:8081/wp-json/wc/v3/products"
$userWC = "utilisateur"
$passWC = "dRaX Mn2Q wgfE CzfQ v6RK x5mv"

# Encodage des identifiants WordPress (Mot de passe d'application)
$EncodedCredentials = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${userWC}:${passWC}"))
$HeadersWoo = @{
    Authorization  = "Basic $EncodedCredentials"
    "Content-Type" = "application/json"
}

# --- 2. TRAITEMENT DU WEBHOOK DOLIBARR ---
$DolibarrData = $PayloadJson | ConvertFrom-Json

$ProductName  = $DolibarrData.object.label
$ProductId    = $DolibarrData.object.id
$ProductPrice = $DolibarrData.object.price
$ProductDesc  = $DolibarrData.object.description

# --- 3. PRÉPARATION ET ENVOI VERS WOOCOMMERCE ---
$WooCommerceData = @{
    name          = $ProductName
    sku           = [string]$ProductId
    regular_price = [string]$ProductPrice
    description   = $ProductDesc
    type          = "simple"
}

$WooCommerceJson = $WooCommerceData | ConvertTo-Json -Depth 5

try {
    $Response = Invoke-RestMethod -Uri $WooUrl -Method Post -Headers $HeadersWoo -Body $WooCommerceJson
    Write-Output "Succès : Produit '$ProductName' créé sur WooCommerce (ID: $($Response.id), SKU: $($ProductId))."
} catch {
    Write-Error "Échec de la création sur WooCommerce : $_"
}
