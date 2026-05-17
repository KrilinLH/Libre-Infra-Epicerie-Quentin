docker exec -i baa37a5e10cd tee /var/www/html/core/triggers/interface_99_all_WooStockSync.class.php << 'EOF'
<?php
// Protection de sécurité standard Dolibarr
if (!defined('NOTOKENRENEWAL')) define('NOTOKENRENEWAL', '1');

require_once DOL_DOCUMENT_ROOT.'/core/triggers/dolibarrtriggers.class.php';

// CORRECTION ICI : Le nom de la classe doit être "Interface" + le nom du trigger
class InterfaceWooStockSync extends DolibarrTriggers
{
    public $family = 'custom';
    public $description = 'Synchronisation professionnelle des stocks vers WooCommerce';
    public $version = '2.1';
    public $picto = 'technic';

    public function __construct($db)
    {
        $this->db = $db;
        $this->name = preg_replace('/^Interface(.+)$/i', '\1', get_class($this));
    }

    public function runTrigger($action, $object, $user, $langs, $conf)
    {
        // On cible les deux actions possibles de modification de stock
        if ($action === 'STOCK_MOVEMENT' || $action === 'STOCK_MODIFY') {
            
            dol_syslog("WooStockSync : Action de stock interceptée (".$action.")", LOG_INFO);

            $product_id = 0;

            // Extraction ultra-sécurisée de l'ID produit
            if (is_object($object)) {
                if (!empty($object->fk_product)) $product_id = $object->fk_product;
                elseif (!empty($object->product_id)) $product_id = $object->product_id;
            } elseif (is_array($object)) {
                if (!empty($object['fk_product'])) $product_id = $object['fk_product'];
                elseif (!empty($object['product_id'])) $product_id = $object['product_id'];
            }

            if ($product_id > 0) {
                dol_syslog("WooStockSync : Produit identifié (ID: ".$product_id."). Préparation du Webhook...", LOG_INFO);

                $payload = json_encode(array(
                    'triggercode' => 'STOCK_MOVEMENT_CREATE',
                    'object' => array(
                        'product_id' => (string)$product_id
                    )
                ));

                // Appel cURL optimisé
                $ch = curl_init('http://172.17.0.1:9000/hooks/produit-stock');
                curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "POST");
                curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
                curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                curl_setopt($ch, CURLOPT_TIMEOUT, 3); // Ne gèle pas Dolibarr
                curl_setopt($ch, CURLOPT_HTTPHEADER, array(
                    'Content-Type: application/json',
                    'Content-Length: ' . strlen($payload)
                ));
                
                $response = curl_exec($ch);
                $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                $curl_error = curl_error($ch);
                curl_close($ch);

                // Analyse de la réponse et log
                if ($http_code >= 200 && $http_code < 300) {
                    dol_syslog("WooStockSync : Succès. Webhook stock transmis avec le code HTTP ".$http_code, LOG_INFO);
                    return 1;
                } else {
                    dol_syslog("WooStockSync : ÉCHEC Webhook. Code HTTP: ".$http_code." / Erreur: ".$curl_error, LOG_ERR);
                    return 0;
                }
            } else {
                dol_syslog("WooStockSync : Impossible d'extraire l'ID du produit de l'objet.", LOG_WARNING);
            }
        }
        
        return 0;
    }
}
?>
EOF
