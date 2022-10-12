# Brief 5 : DNS, TLS et plus si affinité

*Réutilisation du script terraform pour la création d'une machine virtuelle, avec gateway et bastion*

## Chapitre 1 : Créer un sous-domaine

### Création d'un enregistrement DNS pointant vers l'adresse IP de l'application

Sur [Gandi](https://www.gandi.net/fr), dans *Nom de domaine*, il faut choisir le domaine concerné, puis se rendre dans *Enregistrement DNS* et cliquer sur **Ajouter un enregistrement**, en indiquant ce qui est demandé.

![](https://i.imgur.com/KEAptsm.png)

![](https://i.imgur.com/rBLAS3j.png)

### Vérifier la configuration avec le navigateur web

**http:// >sous-domaine< (vote). >domaine< .space**

![](https://i.imgur.com/hf5KuFa.png)

## Chapitre 2 : Créer un certificat

### Installer le plugin Certbot du registrar

Sur une machine Linux, il faut installer python3, pip et certbot.
Ici, il y a eu un cas particulier : à cause d'un problème de versions, il a fallu les installer sur une machine virtuelle.

``sudo apt-get install python3-venv``

``python3 -m venv venv``

``sudo ./venv/bin/pip install certbot``

### Utiliser Certbot pour [créer un certificat](https://github.com/obynio/certbot-plugin-gandi) en utilisant le challenge DNS

Dans les paramètres de Gandi, il y a un onglet *Compte et sécurité*, qui donne accès à une nouvelle page **Sécurité**. Sur cette page, il faut se rendre dans l'onglet *Sécurité*, et y générer une clef d'API.

![](https://i.imgur.com/OtiBcH2.png)

![](https://i.imgur.com/nVF3925.png)

Il faut ensuite installer le plugin **certbot-plugin-gandi** : 
``sudo ./venv/bin/pip install certbot-plugin-gandi``

Il faut ensuite créer un fichier de configuration *gandi.ini*, en indiquant la clé d'API, et en modifier l'attribution des droits (seul l'utilisateur bénéficie des autorisations de lecture et d'écriture) : 
``# live dns v5 api key``

``dns_gandi_api_key=APIKEY``

``chmod 600 gandi.ini``

Il faut ensuite lancer certbot et utiliser le plugin pour authentifier et utiliser le fichier de configuration créé précédemment : 

``sudo ./venv/bin/certbot certonly --authenticator dns-gandi --dns-gandi-credentials /home/celia/gandi.ini -d vote.simplon-celia.space``

## Chapitre 3 : Charger le certificat dans Azure Application Gateway

### Convertir le certificat du format PEM au format PKCS12

Les dossiers dans lesquels le certificat TLS et la clé privée ont été enregistrés dans un emplacement quelconque. Il est donc possible de les déplacer dans un dossier de notre choix, et de se donner tout les droits sur les fichiers.

``sudo cp /etc/letsencrypt/live/vote.simplon-celia.space/fullchain.pem ./fullchain.pem``

``sudo cp /etc/letsencrypt/live/vote.simplon-celia.space/privkey.pem ./privkey.pem``

``sudo chown celia:celia privkey.pem``

``sudo chown celia:celia fullchain.pem``

Concaténation du certificat TLS et de la clé privée dans un seul fichier : 

``cat fullchain.pem privkey.pem > certificat.pem``

Utiliser openssl pour convertir et protéger le fichier PKCS12 avec un mot de passe : 

``openssl pkcs12 -export -out certificat.pfx -in certificat.pem``

### Importation du certificat au format PKCS12 dans une Application Gateway existante sur Terraform et activation du HTTPS sur l’Application Gateway sur le port 443

``resource "azurerm_application_gateway" "gateway" {``

 ``name                = "gateway"``
 
 ``resource_group_name = azurerm_resource_group.rg.name``
 
 ``location            = azurerm_resource_group.rg.location``

`` sku {``

``   name     = "Standard_v2"``

``   tier     = "Standard_v2"``

``   capacity = 2``

`` }``

`` gateway_ip_configuration {``

``   name      = "ip-configuration"``

``   subnet_id = azurerm_subnet.subnet_gateway.id``

`` }``

- Changement du port frontend en Https, port 443

***`` frontend_port {``

***``   name = "https"``

***``   port = 443``

***`` }``***

`` frontend_ip_configuration {``
``   name                 = "front-ip"``
``   public_ip_address_id =`` ``azurerm_public_ip.public_ip_gateway.id``
`` }``

`` backend_address_pool {``
``   name = "backend_pool"``
`` }``

`` backend_http_settings {``
``   name                  = "http-settings"``
``   cookie_based_affinity = "Disabled"``
``   path                  = "/"``
``   port                  = 80``
``   protocol              = "Http"``
``   request_timeout       = 10``
`` }``

- Configuration du listener en protocole https, et ajout du nom du certificat

***`` http_listener {``
``   name                           = "listener"``
``   frontend_ip_configuration_name = "front-ip"``
``   frontend_port_name             = "https"``
``   protocol                       = "Https"``
``   ssl_certificate_name = "certificat"``
`` }``***

`` request_routing_rule {``
``   name                       = "rule-1"``
``   rule_type                  = "Basic"``
``   http_listener_name         = "listener"``
``   backend_address_pool_name  = "backend_pool"``
``   backend_http_settings_name = "http-settings"``
``   priority                   = 100``
`` }``

- Ajout du certificat TLS (chemin et mot de passe)

***`` ssl_certificate {``
``  name = "certificat"``
``  data = "${filebase64(("//wsl$/Ubuntu/home/celia/certificat.pfx"))}"``
``  password = "*****"``
`` }``***
``}``

## Chapitre 4 : Chargement du certificat dans Azure KeyVault en utilisant Azure CLI

- Création du keyvault
``az keyvault create --resource-group Brief5-Celia --name B5vault --location westus``

- Importation du certificat
``az keyvault certificate import --file //wsl$/Ubuntu/home/celia/certificat.pfx --name certificat --vault-name B5vault --password nabangba``

- Importation de la clé privée
``az keyvault key import -n privkey --pem-file //wsl$/Ubuntu/home/celia/privkey.pem --vault-name B5vault``

- Vérification que le certificat est dans le keyvault
``az keyvault certificate show --vault-name B5vault --name certificat``
