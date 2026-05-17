<?php
require_once DOL_DOCUMENT_ROOT.'/core/triggers/dolibarrtriggers.class.php';

class interface_99_all_WooStockSync extends DolibarrTriggers
{
    public $family = 'custom';
    public $description = 'Trigger personnalisé pour synchroniser instantanément les mouvements de stock';
    public $version = '1.0';
    public $picto = 'stock';

    public function __construct($db)
    {
        $this->db = $db;
    }

    public function runTrigger($action, $object, $user, $langs, $conf)
    {
        // On intercepte le vrai signal PHP du mouvement de stock
        if ($action === 'STOCK_MOVEMENT_CREATE') {
            
            // On s'assure que l'ID du produit est bien présent dans le mouvement
            if (!empty($object->product_id)) {
                
                // On prépare le payload minimal avec l'ID du produit pour le script PowerShell
                $payload = json_encode(array(
                    'triggercode' => 'STOCK_MOVEMENT_CREATE',
                    'object' => array(
                        'product_id' => (string)$object->product_id
                    )
                ));

                // Envoi direct en POST vers ton utilitaire webhook sur Ubuntu
                $ch = curl_init('http://172.17.0.1:9000/hooks/produit-stock');
                curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "POST");
                curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
                curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                curl_setopt($ch, CURLOPT_TIMEOUT, 5); 
                curl_setopt($ch, CURLOPT_HTTPHEADER, array(
                    'Content-Type: application/json',
                    'Content-Length: ' . strlen($payload)
                ));
                
                curl_exec($ch);
                curl_close($ch);
            }
        }
        
        return 1;
    }
}
?>
