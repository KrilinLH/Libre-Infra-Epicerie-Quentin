param(
    [Parameter(Mandatory=$true)]
    [string]$PayloadJson
)

# --- 1. CONFIGURATION WOOCOMMERCE API ---
$WooBaseUrl = "http://192.168.17.131:8081/wp-json/wc/v3/products"
$userWC     = "utilisateur"
$passWC     = "dRaX Mn2Q wgfE CzfQ v6RK x5mv"

$EncodedCredentials = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${userWC}:${passWC}"))
$HeadersWoo = @{
    Authorization  = "Basic $EncodedCredentials"
    "Content-Type" = "application/json"
}

# --- 2. TRAITEMENT DU WEBHOOK DOLIBARR ---
$DolibarrData = $PayloadJson | ConvertFrom-Json

# Récupération de l'ID du produit envoyé par notre trigger PHP personnalisé
$ProductId = ([string]$DolibarrData.object.product_id).Trim()

if ([string]::IsNullOrEmpty($ProductId)) {
    Write-Error "Échec : Impossible de récupérer l'ID du produit dans le payload."
    return
}

try {
    # --- 3. REQUÊTE SQL DIRECTE DANS MARIADB DOCKER ---
    Write-Output "Interrogation de MariaDB pour le produit ID '$ProductId'..."
    
    # Requête pour sommer le stock réel de tous les entrepôts pour ce produit
    $SqlQuery = "SELECT SUM(reel) as total_stock FROM llx_product_stock WHERE fk_product = $ProductId;"
    
    # Exécution de la commande SQL via le conteneur Docker dolibarr-db
    $SqlResult = docker exec dolibarr-db mysql -u dolibarr -pdolipassword -D dolibarr -e "$SqlQuery" -B -N
    
    # Nettoyage du résultat (si NULL ou vide, le stock est égal à 0)
    $RealStock = $SqlResult.Trim()
    if ([string]::IsNullOrEmpty($RealStock) -or $RealStock -eq "NULL") {
        $RealStock = "0"
    }

    Write-Output "Stock réel trouvé dans Dolibarr pour l'ID $ProductId : $RealStock"

    # --- 4. RECHERCHE DE L'ID WOOCOMMERCE VIA LE SKU ---
    $SearchUrl = "{0}?sku={1}" -f $WooBaseUrl, $ProductId
    $SearchResult = Invoke-RestMethod -Uri $SearchUrl -Method Get -Headers $HeadersWoo

    if ($SearchResult.Count -eq 0) {
        Write-Error "Échec : Aucun produit trouvé sur WooCommerce avec le SKU '$ProductId'."
        return
    }

    $WooCommerceId = $SearchResult[0].id

    # --- 5. ENVOI DE LA MISE À JUR DU STOCK À WOOCOMMERCE (PUT) ---
    $WooCommerceData = @{
        manage_stock   = $true
        stock_quantity = [int]$RealStock
    }
    $WooCommerceJson = $WooCommerceData | ConvertTo-Json -Depth 5

    $UpdateUrl = "{0}/{1}" -f $WooBaseUrl, $WooCommerceId
    $Response = Invoke-RestMethod -Uri $UpdateUrl -Method Put -Headers $HeadersWoo -Body $WooCommerceJson
    
    Write-Output "Succès : Stock mis à jour sur WooCommerce (ID WC: $WooCommerceId, SKU: $ProductId, Quantité: $RealStock)."

} catch {
    Write-Error "Échec lors du processus de synchronisation du stock : $_"
}
