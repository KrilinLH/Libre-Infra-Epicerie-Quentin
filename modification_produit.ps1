param(
    [Parameter(Mandatory=$true)]
    [string]$PayloadJson
)

# --- 1. CONFIGURATION WOOCOMMERCE API ---
$WooBaseUrl = "http://192.168.17.131:8081/wp-json/wc/v3/products"
$userWC     = "utilisateur"
$passWC     = "dRaX Mn2Q wgfE CzfQ v6RK x5mv"

# Encodage des identifiants WordPress (Mot de passe d'application)
$EncodedCredentials = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${userWC}:${passWC}"))
$HeadersWoo = @{
    Authorization  = "Basic $EncodedCredentials"
    "Content-Type" = "application/json"
}

# --- 2. TRAITEMENT DU WEBHOOK DOLIBARR ---
$DolibarrData = $PayloadJson | ConvertFrom-Json

$ProductName  = $DolibarrData.object.label
# On force le nettoyage de l'ID pour éviter tout espace ou caractère invisible
$ProductId    = [string]$DolibarrData.object.id
$ProductId    = $ProductId.Trim()

$ProductPrice = $DolibarrData.object.price
$ProductDesc  = $DolibarrData.object.description

try { 
    # --- 3. RECHERCHE DE L'ID WOOCOMMERCE VIA LE SKU ---
    Write-Output "Recherche du produit avec le SKU '$ProductId' sur WooCommerce..."

    # Construction sécurisée de l'URL de recherche
    $SearchUrl = "{0}?sku={1}" -f $WooBaseUrl, $ProductId
    $SearchResult = Invoke-RestMethod -Uri $SearchUrl -Method Get -Headers $HeadersWoo

    # Vérification si le produit existe bien sur WooCommerce
    if ($SearchResult.Count -eq 0) {
        Write-Error "Échec : Aucun produit trouvé sur WooCommerce avec le SKU '$ProductId'. Impossible de le modifier."
        return
    }

    # On récupère l'ID WooCommerce interne du premier produit correspondant trouvé
    $WooCommerceId = $SearchResult[0].id

    # --- 4. PRÉPARATION DES DONNÉES DE MISE À POUR ---
    $WooCommerceData = @{
        name          = $ProductName
        regular_price = [string]$ProductPrice
        description   = $ProductDesc
    }
    $WooCommerceJson = $WooCommerceData | ConvertTo-Json -Depth 5

    # --- 5. ENVOI DE LA MODIFICATION VIA MÉTHODE PUT ---
    # Construction sécurisée de l'URL de mise à jour
    $UpdateUrl = "{0}/{1}" -f $WooBaseUrl, $WooCommerceId
    $Response = Invoke-RestMethod -Uri $UpdateUrl -Method Put -Headers $HeadersWoo -Body $WooCommerceJson
     Write-Output "Succès : Produit '$ProductName' mis à jour sur WooCommerce (ID WC: $WooCommerceId, SKU: $ProductId)."

} catch {
    Write-Error "Échec lors du processus de modification sur WooCommerce : $_"
}
