import requests
from woocommerce import API

# ==========================================
# 1. CONFIGURATION
# ==========================================
DOLI_URL = "http://192.168.17.131:8080/api/index.php"
DOLI_KEY = "d3iFuZYq3i0Yi8Q84uX9rIrM0CO7Kv7x"

DOLI_BASE_URL = "http://192.168.17.131:8080"

wcapi = API(
    url="http://192.168.17.131:8081",
    consumer_key="ck_e568587811d4d431f39f489e6d623e287863efd7",
    consumer_secret="cs_8c574e70f1220a93ba0548a120c463913d96613f",
    version="wc/v3",
    timeout=20
)

# ==========================================
# 2. DOLIBARR - PRODUITS
# ==========================================
def get_dolibarr_products():
    try:
        print("📦 Récupération produits Dolibarr...")
        headers = {
            "DOLAPIKEY": DOLI_KEY,
            "Accept": "application/json"
        }
        r = requests.get(f"{DOLI_URL}/products?limit=100", headers=headers)

        if r.status_code != 200:
            print(f"❌ Erreur Dolibarr produits (Code {r.status_code}) : {r.text}")
            return []
        return r.json()

    except Exception as e:
        print(f"❌ Exception produits Dolibarr: {e}")
        return []

# ==========================================
# 3. IMAGES (GESTION DU DOSSIER PAR RÉFÉRENCE)
# ==========================================
def get_dolibarr_images(product):
    try:
        product_id = product.get("id")
        product_ref = product.get("ref")

        if not product_id:
            return []

        headers = {"DOLAPIKEY": DOLI_KEY}
        r = requests.get(
            f"{DOLI_URL}/documents",
            headers=headers,
            params={"modulepart": "product", "id": product_id},
            timeout=10
        )

        if r.status_code == 404 or r.status_code != 200:
            return []

        files = r.json()
        images = []

        for f in files:
            try:
                filename = f.get("filename") or f.get("relativename") or ""
                folder = f.get("level1name") or product_ref

                if filename and filename.lower().endswith((".jpg", ".jpeg", ".png", ".webp")):
                    url = f"{DOLI_BASE_URL}/produit/{folder}/{filename}"

                    test_req = requests.get(url, stream=True, timeout=5)
                    if test_req.status_code == 200:
                        images.append({"src": url})
            except Exception:
                continue

        return images

    except Exception as e:
        print(f"⚠️ Erreur images produit {product.get('ref')}: {e}")
        return []

# ==========================================
# 4. SYNC PRODUIT (CRÉATION ET MISE À JOUR)
# ==========================================
def sync_product(product):
    try:
        sku = product.get("ref")
        label = product.get("label")
        price = product.get("price_ttc")
        stock = product.get("stock_reel")
        description = product.get("description") or ""

        if not sku:
            return

        print(f"🔄 Sync: {label}")
        images = get_dolibarr_images(product)

        # Recherche pour voir si le produit existe déjà
        r_search = wcapi.get("products", params={"sku": sku})

        if r_search.status_code == 200 and len(r_search.json()) > 0:
            # --- CAS 1 : MISE À JOUR (UPDATE) ---
            woo_product = r_search.json()[0]
            woo_id = woo_product["id"]
            woo_images = woo_product.get("images", [])

            data_update = {
                "stock_quantity": int(stock) if stock else 0,
                "regular_price": str(price) if price else "0",
                "description": description
            }

            if images and len(woo_images) == 0:
                data_update["images"] = images
                print(f"   📸 Ajout de l'image manquante")

            wcapi.put(f"products/{woo_id}", data_update)
            print(f"✅ Update: {label}")

        else:
            # --- CAS 2 : CRÉATION ORIGINALE (CREATE) ---
            data_create = {
                "name": label,
                "type": "simple",
                "sku": sku,
                "regular_price": str(price) if price else "0",
                "stock_quantity": int(stock) if stock else 0,
                "manage_stock": True,
                "status": "publish",
                "description": description if description else "Produit importé depuis Dolibarr",
                "short_description": "Sync auto Dolibarr"
            }

            if images:
                data_create["images"] = images

            r_create = wcapi.post("products", data_create)

            if r_create.status_code == 201:
                print(f"🚀 Création originale réussie : {label}")
            else:
                print(f"❌ Erreur lors de la création : {label} -> {r_create.text}")

    except Exception as e:
        print(f"❌ Erreur sync produit {product.get('ref')}: {e}")

# ==========================================
# 5. MAIN
# ==========================================
if __name__ == "__main__":
    print("🚀 START SYNC DOLIBARR → WOOCOMMERCE")
    products = get_dolibarr_products()

    for p in products:
        try:
            if p.get("status") == "1":
                sync_product(p)
        except Exception as e:
            print(f"⚠️ Skip product error: {e}")

    print("🏁 SYNC FINISHED")
