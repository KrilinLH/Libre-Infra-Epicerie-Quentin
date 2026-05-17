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

# Lors d'une suppression, Dolibarr envoie l'ID dans l'objet principal
$ProductId = ([string]$DolibarrData.object.id).Trim()

try {
    # --- 3. RECHERCHE DE L'ID WOOCOMMERCE VIA LE SKU ---
    Write-Output "Recherche du produit à supprimer avec le SKU '$ProductId' sur WooCommerce..."
    
    $SearchUrl = "{0}?sku={1}" -f $WooBaseUrl, $ProductId
    $SearchResult = Invoke-RestMethod -Uri $SearchUrl -Method Get -Headers $HeadersWoo

    # Vérification si le produit existe sur WooCommerce
    if ($SearchResult.Count -eq 0) {
        Write-Output "Information : Aucun produit trouvé sur WooCommerce avec le SKU '$ProductId'. Déjà supprimé ou inexistant."
        return
    }

    # On récupère l'ID WooCommerce interne du produit trouvé
    $WooCommerceId = $SearchResult[0].id

    # --- 4. ENVOI DE LA REQUÊTE DE SUPPRESSION DEFINITIVE (DELETE) ---
    # force=true permet de sauter la corbeille WordPress et de supprimer définitivement
    $DeleteUrl = "{0}/{1}?force=true" -f $WooBaseUrl, $WooCommerceId
    
    $Response = Invoke-RestMethod -Uri $DeleteUrl -Method Delete -Headers $HeadersWoo
    
    Write-Output "Succès : Le produit avec le SKU '$ProductId' (ID WC: $WooCommerceId) a été supprimé définitivement de WooCommerce."

} catch {
    Write-Error "Échec lors du processus de suppression sur WooCommerce : $_"
}
