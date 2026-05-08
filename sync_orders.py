import requests
import time

# --- CONFIGURATION ---
# WooCommerce
WC_URL = "http://localhost:8081/wp-json/wc/v3/orders"
WC_USER = "utilisateur"
WC_PASS = "dRaX Mn2Q wgfE CzfQ v6RK x5mv"

# Dolibarr
DOLI_URL = "http://192.168.17.131:8080/api/index.php"
DOLI_KEY = "d3iFuZYq3i0Yi8Q84uX9rIrM0CO7Kv7x"
DOLI_HEADERS = {"DOLAPIKEY": DOLI_KEY}
DOLI_WAREHOUSE_ID = 1  # <--- METTEZ VOTRE ID D'ENTREPÔT ICI

def get_or_create_thirdparty(email, name):
    """Vérifie l'existence du tiers ou le crée."""
    r = requests.get(f"{DOLI_URL}/thirdparties", headers=DOLI_HEADERS, params={"sqlfilters": f"(t.email:=:'{email}')"})
    if r.status_code == 200:
        data = r.json()
        if isinstance(data, list) and len(data) > 0:
            return data[0]['id']

    payload = {"name": name, "email": email, "client": 1, "status": 1}
    r = requests.post(f"{DOLI_URL}/thirdparties", headers=DOLI_HEADERS, json=payload)
    return r.json()

def get_product_id_by_sku(sku):
    """Cherche l'ID produit via son SKU (Référence)."""
    if not sku: return None
    r = requests.get(f"{DOLI_URL}/products", headers=DOLI_HEADERS, params={"sqlfilters": f"(t.ref:=:'{sku}')"})
    if r.status_code == 200:
        data = r.json()
        if isinstance(data, list) and len(data) > 0:
            return data[0]['id']
    return None

def order_exists(wc_id):
    """Vérifie si la commande WC existe déjà dans Dolibarr."""
    r = requests.get(f"{DOLI_URL}/orders", headers=DOLI_HEADERS, params={"sqlfilters": f"(t.ref_client:=:'{wc_id}')"})
    if r.status_code == 200:
        data = r.json()
        # On vérifie strictement que l'ID est dans la liste renvoyée
        if isinstance(data, list):
            return any(str(order.get('ref_client')) == str(wc_id) for order in data)
    return False

def sync():
    """Récupère, crée et VALIDE les commandes avec mouvement de stock."""
    print(f"🚀 Synchro lancée (Entrepôt ID: {DOLI_WAREHOUSE_ID})...")

    # Récupération uniquement des commandes validées (processing) ou en attente de virement/chèque (on-hold)
    response = requests.get(WC_URL, auth=(WC_USER, WC_PASS), params={"status": "processing,on-hold"})

    if response.status_code != 200:
        print(f"❌ Erreur WC : {response.text}")
        return

    for wc_order in response.json():
        wc_id = str(wc_order['id'])

        if order_exists(wc_id):
            print(f"⏭️ Commande #{wc_id} déjà synchronisée.")
            continue

        socid = get_or_create_thirdparty(wc_order['billing']['email'], f"{wc_order['billing']['first_name']} {wc_order['billing']['last_name']}")

        order_data = {
            "socid": socid,
            "date": int(time.time()),
            "ref_client": wc_id,
            "lines": []
        }

        for item in wc_order['line_items']:
            prod_id = get_product_id_by_sku(item['sku'])
            line = {
                "libelle": item['name'],
                "qty": item['quantity'],
                "subprice": item['price'],
                "tva_tx": 20.0,
                "product_type": 0
            }
            if prod_id:
                line["fk_product"] = prod_id
            order_data["lines"].append(line)

        # Création
        res = requests.post(f"{DOLI_URL}/orders", headers=DOLI_HEADERS, json=order_data)
        if res.status_code == 200:
            doli_id = res.json()
            # VALIDATION avec l'ID de l'entrepôt pour décrémenter le stock
            val_payload = {"idwarehouse": DOLI_WAREHOUSE_ID}
            val_res = requests.post(f"{DOLI_URL}/orders/{doli_id}/validate", headers=DOLI_HEADERS, json=val_payload)

            if val_res.status_code == 200:
                print(f"✅ Commande #{wc_id} validée et stock décrémenté !")
            else:
                print(f"⚠️ Commande #{wc_id} créée mais échec validation : {val_res.text}")
        else:
            print(f"❌ Erreur création commande #{wc_id} : {res.text}")

if __name__ == "__main__":
    sync()
