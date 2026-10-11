# MPB Check

Appli Android : tu colles (ou partages) le lien d'une annonce Leboncoin, elle te dit
combien MPB te la reprendrait, quelle marge tu peux faire, et tu peux poser des
questions à l'IA sur l'annonce.

## Nouveautés de la v2
- **Vrai prix de reprise MPB** : l'appli interroge l'API publique de reprise de MPB
  (`/public-api/v1/models/purchase-price/<id>/<état>/`, en-tête `X-Market: fr`) et récupère
  les 5 prix (Comme neuf → Très usé). La marge principale utilise l'état annoncé sur
  Leboncoin, et une **marge prudente** utilise l'état juste en dessous.
- **Partage direct** : dans l'appli Leboncoin, *Partager › MPB Check* lance l'analyse
  tout de suite (réception de `ACTION_SEND text/*` via `receive_sharing_intent`).
- **Presse-papiers** : au lancement et au retour dans l'appli, si un lien Leboncoin a été
  copié, une bannière propose « Analyser l'annonce copiée ? ». Le lien est extrait du texte
  partagé par une simple regex (`extractLeboncoinUrl`), sans IA.
- **Nouvelle interface** Material 3 : thème sombre par défaut (clair dans les réglages),
  accent violet, polices Inter et Manrope (`google_fonts`), cartes arrondies.
- **Analyse en étapes animées** : Lecture de l'annonce → Identification → Catalogue MPB →
  Calcul. La page Leboncoin est repliée, et se déplie toute seule si Leboncoin demande
  une vérification.
- **Écran résultat** : marge en très gros (vert / orange / rouge) avec verdict,
  prix annonce → reprise MPB, carte annonce (état, marque, description repliable),
  une carte par élément (nom MPB, reprise, badge « Prix MPB réel », mini-échelle des
  5 prix avec l'état retenu mis en avant, nombre en vente chez MPB, lien vers la page MPB), alertes en
  bandeaux (⛔ « pour pièces » en rouge, en haut).
- **Historique** : les 50 dernières analyses, en local. Un appui rouvre le résultat sans
  nouvel appel ; glisser vers la gauche pour supprimer (avec « Annuler »).
- **Poser une question** : chat avec Gemini qui connaît l'annonce et toute l'analyse,
  avec recherche Google (sources cliquables sous la réponse) et rendu Markdown.
  La conversation est enregistrée avec l'analyse.
- **Icône** de l'appli (`assets/icon/`), générée pour Android pendant le build.

## Comment ça marche
1. **Lecture de l'annonce** : la page s'ouvre dans un navigateur intégré (WebView), comme si
   tu la consultais. Le titre, la description, le prix et l'état sont lus dans les données
   de la page. Si Leboncoin affiche une vérification, elle apparaît à l'écran et c'est toi
   qui la fais.
2. **Gemini Flash-Lite** comprend l'annonce : boîtier(s), objectif(s), flash, version
   exacte (IS, STM, VR…), défauts, nombre de déclenchements.
3. **Catalogue MPB** : l'appli cherche les noms exacts chez MPB, puis Gemini choisit le bon.
4. **Accès à MPB par WebView** : l'anti-robot de MPB refuse (HTTP 403) le client HTTP de
   l'appli. Les appels MPB partent donc d'une page mpb.com ouverte dans une WebView
   repliée (`lib/services/mpb_web_transport.dart`), comme un vrai navigateur. Si MPB
   demande une vérification, la WebView se déplie pour que tu la fasses.
5. **Identification par l'IA partout** (`gemini-flash-lite-latest`) : Gemini lit
   l'annonce (y compris les noms abrégés : « Sony a68 » → Sony Alpha SLT-A68), puis
   choisit le nom exact parmi les candidats du catalogue MPB. Le moteur local
   (`lib/services/local_identifier.dart`) ne sert qu'en **secours** si l'IA ne répond pas
   (quota, réseau) : l'écran résultat l'indique et les modèles restent « à vérifier ».
   **Vérification de correspondance** (`lib/services/match_check.dart`) : après
   l'identification, un garde-fou sans IA contrôle que la marque de chaque modèle figure
   dans l'annonce (sinon verdict « non »), puis Gemini rend un verdict **oui / doute /
   non**. Hors « oui », une alerte s'affiche et les modèles sont marqués incertains.
   Sans verdict « oui », aucun message n'est envoyé automatiquement.
5 bis. **Catalogue local des noms exacts** : le moteur de recherche MPB ne trouve un modèle
   qu'avec son nom quasi exact (« Sony A68 » ne trouve pas « Sony Alpha SLT-A68 »).
   L'appli télécharge donc une fois la liste complète des modèles MPB (nom exact +
   identifiant), la garde en local (`lib/services/mpb_catalog.dart`) et la rafraîchit
   chaque semaine (bouton « Retélécharger » dans les réglages). Chaque élément est
   comparé en local, en donnant plus de poids aux références (A68, 1200D, 18-55…) :
   nom exact → retenu directement, sans IA ; sinon les noms les plus proches sont
   proposés à Gemini. L'identifiant vient aussi du catalogue (un appel de moins).
   Le moteur de recherche MPB ne sert plus qu'en secours.
   **Voir le catalogue** : Réglages › Catalogue MPB › « Voir le catalogue » liste tous les
   noms exacts avec leur identifiant MPB (recherche, copie CSV, export PDF). C'est la
   liste avec laquelle l'IA fait la correspondance. Si l'IA ne retient aucun candidat
   alors qu'un seul porte exactement la même référence (A68, 1200D…), il est pris
   automatiquement mais marqué « à vérifier ». Un élément non trouvé dans le catalogue
   donne le verdict « doute » : jamais d'envoi automatique.
6. **Prix de reprise réel** :
   - identifiant MPB du modèle : `GET /search-service/product/query/` avec
     `filter_query[object_type]=model` et le nom exact (marche aussi hors stock) ;
   - 5 prix : `GET /public-api/v1/models/purchase-price/<id>/<état>/` avec `X-Market: fr`
     (sinon prix en GBP ; la devise `EUR` est vérifiée). Appels en séquence (~300 ms
     d'écart), cache local de 24 h par id + état ;
   - état retenu d'après l'attribut « État » de l'annonce :

     | Leboncoin | MPB |
     |---|---|
     | État neuf | `like-new` |
     | Très bon état | `excellent` |
     | Bon état | `good` |
     | État satisfaisant | `well-used` |
     | Pour pièces | aucun rachat (0 € + alerte ⛔) |
     | inconnu | `good` |

   - marge = reprise pour l'état annoncé − prix ; marge prudente = même calcul avec
     l'état juste en dessous.
   - **Secours** si l'API ne répond pas : ancienne estimation enregistrée
     (`lib/data/real_quotes.dart`), sinon médiane de revente MPB en état Bon × 0,54
     (boîtier) ou × 0,40 (objectif). C'est alors affiché « estimation approximative ».
7. **Résultat**, puis questions éventuelles à l'IA (qui connaît aussi les 5 prix de
   chaque élément).

Saisie manuelle : bouton « Saisir le texte à la main » sous le champ du lien.

## Radar : analyse automatique des recherches enregistrées

L'appli Leboncoin envoie une notification par recherche enregistrée (titre = nom de la
recherche, texte « De nouveaux résultats sont disponibles »). Le radar s'en sert comme
déclencheur : il ouvre la recherche, trouve les nouvelles annonces et les analyse tout seul.

### Mise en route
1. Onglet **Radar** › menu › **Permissions et réglages** : les trois lignes doivent être vertes.
   - **Accès aux notifications** : active « MPB Check Radar ».
   - **Optimisation de la batterie désactivée** : obligatoire, c'est ce qui autorise le
     service de premier plan à démarrer en arrière-plan (Android 12+).
   - **Notifications de MPB Check** (Android 13+).
2. Onglet **Radar** › icône loupe › **Ajouter** : nom = **exactement** le titre de la
   notification Leboncoin (« objectif », « TOUTES CATÉGORIES »… ; casse et accents
   ignorés), URL `leboncoin.fr/recherche?…` (`sort=time` est ajouté si absent), prix max
   (200 € par défaut), catégorie (16 = Photo, audio & vidéo par défaut).
   Une notification reçue sans recherche associée apparaît dans **Notifications reçues**,
   avec un bouton « Créer la recherche ».

### Fonctionnement
- `RadarNotificationListener.kt` reçoit les notifications dont le package contient
  « leboncoin », met l'événement en file et lance `RadarService.kt` (service de premier plan
  court, notification discrète « Radar : … »). La notification de recherche est ensuite
  **retirée** pour pouvoir réapparaître normalement (les messages Leboncoin ne sont pas touchés).
- Le service démarre le code Dart du radar (`radarMain`, `lib/radar/`) dans un moteur Flutter
  sans écran. Un seul traitement à la fois ; plusieurs notifications sont fusionnées ; au
  moins 60 s entre deux chargements d'une même recherche.
- La page de recherche est lue dans une WebView sans affichage (`HeadlessBrowser.kt`, cookies
  partagés avec la WebView visible) : `__NEXT_DATA__ › props.pageProps.searchData.ads`.
- **Nouvelles annonces** : la 1re fois, les **3 plus récentes** ; ensuite, **toutes celles
  parues depuis la dernière vue** (point de reprise enregistré par recherche + table des
  annonces vues). Les annonces boostées, en tête mais souvent anciennes, sont triées par date.
  Gardées si : jamais vue, prix ≤ max, bonne catégorie, publiée (ou **remontée en tête**,
  `index_date`) il y a moins de 24 h. Une notification déclencheur dont le titre ne
  correspond à aucun nom lance toutes les recherches actives.
- **Analyse en 2 temps** : (a) pré-analyse sur titre + attributs (Gemini + prix MPB réel) ;
  si la marge provisoire < seuil − 15 €, on s'arrête là ; (b) sinon la page de l'annonce est
  ouverte et analysée avec sa description.
- **Résultat** : notification si marge ≥ seuil (« +45 € · Canon EOS 1200D + 18-55 »,
  « 50 € → reprise 95 € (Excellent) · objectif », boutons Annonce / Analyse ; priorité haute
  si marge ≥ 2 × seuil). Fil complet dans l'onglet Radar (rentables en haut), filtre par
  recherche, appui → écran résultat avec le chat IA. Tableau de bord du jour.

### Notification déclencheur
Seule la notification Leboncoin **choisie** lance le radar (et est retirée ensuite) ; les
autres (messages, offres…) sont ignorées. Radar › menu › **Notification à écouter** (ou
depuis le test global) : attends une notification de recherche, reviens dans l'appli et
appuie sur « Écouter celle-ci ». Sans choix, le radar reconnaît le texte habituel
« … nouveaux résultats … ».

### Fonctionnement en arrière-plan
L'appli n'a pas besoin de tourner en permanence : Android garde l'écoute des notifications
branchée et réveille l'appli à chaque notification. Pour que le système ne la coupe pas :
accès aux notifications, optimisation de batterie désactivée, batterie « Non restreinte »
(Samsung : retirer des applis en veille ; Huawei : Batterie › Lancement d'applis › gérer
manuellement, 3 options activées ; Xiaomi : démarrage automatique). L'écouteur se
rebranche tout seul s'il est débranché, et un **chien de garde** (toutes les 15 min) envoie
une notification **« Radar arrêté »** si l'écoute est coupée, l'accès retiré, l'arrière-plan
restreint ou un démarrage refusé.

### En direct
En haut de l'onglet Radar, la carte **En direct** montre ce que fait le radar à la seconde :
recherche en cours, annonce analysée (titre, prix, n/m), étape (chargement, pré-analyse,
ouverture de l'annonce, analyse complète, résultat) et les dernières actions du journal.
Sinon « En attente » avec l'heure du dernier passage ; « Interrompu ? » si le radar ne
donne plus de nouvelles depuis 3 min. Le fil des annonces se met à jour toutes les 5 s.

### Test global, toutes les annonces, PDF
- **Test global** (Radar › Test) : autorisations, écoute des notifications, déclencheur,
  service en arrière-plan, chien de garde, chaque clé Gemini, catalogue MPB, identification
  sans IA, API de reprise MPB, lecture d'une page Leboncoin, état du radar. Rapport copiable.
- **Toutes les annonces** (Radar › Tout voir) : les analysées (marge, recherche texte, filtre
  « rentables », par recherche) et toutes les annonces vues avec ce que le radar en a fait
  (analysée, trop chère, trop ancienne, antérieure au point de reprise…).
- **Export PDF** (Radar › PDF, Tout voir, ou historique de l'onglet Analyse) : toutes les
  annonces du radar, seulement les rentables, ou l'historique ; aujourd'hui / 7 j / 30 j /
  tout. Tableau + détail (modèles MPB, 5 prix de reprise, alertes, liens). Partage Android.

### Limites et sécurité
- 30 pages d'annonces par heure au maximum, 3 s minimum entre deux pages Leboncoin.
- **Vérification Leboncoin** (captcha / DataDome) : le radar s'arrête et envoie une
  notification « Leboncoin demande une vérification ». À l'appui, la page s'ouvre dans une
  WebView **visible** : tu fais la vérification toi-même, puis « C'est fait » relance le radar.
  Aucun contournement, aucune résolution automatique.
- 3 échecs réseau de suite : pause de 30 min.
- **Filet de sécurité** (désactivé par défaut) : WorkManager relance les recherches actives
  toutes les 60 min, avec les mêmes limites.
- Journal : Radar › menu › Journal (ou Réglages › Journal du radar).
- Stockage : sqflite (`radar.db` : recherches, annonces vues, analyses, notifications, journal).

### Fichiers
- `android_native/kotlin/` : code Kotlin copié dans le projet Android par `tool/patch_radar.py`
  (qui ajoute aussi les permissions FOREGROUND_SERVICE(_DATA_SYNC), POST_NOTIFICATIONS,
  REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, le service BIND_NOTIFICATION_LISTENER_SERVICE et les
  dépendances androidx).
- `lib/radar/` : base de données, moteur, navigateur sans affichage, pont Android.
- `lib/screens/radar_*.dart` : écrans du radar.

## v3 : du « bon plan » au « bénéfice réel »

### Analyse des photos
- Les photos sont lues dans la page de l'annonce (`__NEXT_DATA__` : `images.urls_large`, sinon
  `urls`, sinon `thumb_url`). L'appli en garde 6 au plus, les réduit à environ 1024 px en JPEG et les
  envoie à Gemini (`lib/services/photo_check.dart`).
- Gemini renvoie :
  - le modèle visible ;
  - la cohérence avec l'annonce (oui / non / doute) ;
  - l'état visuel (barème MPB) ;
  - les défauts, avec leur gravité et la photo concernée ;
  - les accessoires visibles.
- **Prix MPB** : il est calculé sur l'état le plus bas entre l'état annoncé et l'état visuel.
- **Photos incohérentes** : si l'IA répond « non », c'est un verdict de correspondance « non » ;
  si elle répond « doute », c'est « doute ».
- **Défaut majeur** (écran cassé, lentille rayée, champignon, buée) : alerte rouge, et jamais
  d'envoi automatique.
- **Écran résultat** : carrousel des photos avec les défauts marqués, et badge « Photos vérifiées ».
- **Radar** : les photos ne sont analysées qu'après la pré-analyse, donc seulement pour les
  annonces prometteuses.

### Marge nette
- **Réglages › Marge nette** :
  - ville ou code postal (position trouvée via la Base Adresse Nationale) ;
  - coût au km (0,15 € par défaut) ;
  - distance max pour une remise en main propre (30 km par défaut) ;
  - frais Leboncoin en pourcentage et en fixe (0 par défaut, avec un lien vers l'aide Leboncoin) ;
  - frais d'envoi estimés.
- **Lieu et livraison** : lus dans l'annonce (`location`, attributs `shippable` et `shipping_type`).
- **Calcul** : marge nette = reprise MPB − prix − frais Leboncoin − (livraison, ou trajet
  aller-retour × coût/km). La distance est estimée par la route (vol d'oiseau × 1,25). Les frais
  Leboncoin ne comptent que pour un achat en ligne. Si la livraison est possible et que la main
  propre revient moins cher à moins de la distance max, c'est la main propre qui compte.
- **Trop loin** : si la remise est en main propre seulement et au-delà de la distance max,
  l'alerte « trop loin » s'affiche et rien n'est envoyé automatiquement.
- **Utilisation** : le Radar, les notifications, le prix max et l'envoi automatique utilisent la
  marge **nette**. Le détail du calcul est sur l'écran résultat.

### Onglet Stock
- **Fiche** : « Je l'ai acheté » crée une fiche avec l'annonce, le prix payé, les frais réels
  (préremplis avec les coûts calculés), la date, les éléments, l'état constaté à réception et la
  reprise estimée.
- **Statuts** : Acheté → Reçu → Estimation MPB faite → Expédié à MPB → Payé par MPB (montant
  réellement payé), ou « Revendu ailleurs ».
- **Tableau de bord** : bénéfice total, bénéfice du mois, nombre d'achats, bénéfice moyen, meilleur
  coup, et précision (montant payé par MPB comparé à l'estimation, en € et en %).
- **Export** : CSV, séparateur « ; », à partager.
- **Stockage** : sqflite (table `deals`, base v5).

### Réponses des vendeurs
- **Détection** : l'écouteur de notifications repère aussi les messages Leboncoin (catégorie,
  canal ou style « conversation »). Ces notifications ne sont jamais retirées.
- **Rattachement** : chaque message est rattaché à une annonce contactée par les mots de son titre.
  À défaut, il est rattaché à la seule annonce contactée dans les 7 derniers jours.
- **Notification « <vendeur> a répondu »** : elle ouvre la messagerie dans le navigateur connecté,
  sur la conversation de l'annonce.
- **Propositions** : « Proposer des réponses » lit les derniers messages. Gemini propose alors
  2 ou 3 réponses dans le ton réglé : accepter, contre-offre (jamais au-dessus du prix max en marge
  nette) ou poser une question.
- **Envoi** : je choisis une réponse et je peux la modifier. L'appli l'écrit et l'envoie
  **après ma confirmation**. Il n'y a jamais de réponse automatique.
- **Statuts** : contacté → réponse reçue → accord → acheté. « Acheté » crée la fiche du Stock.

### Tests
- Fichier : `test/v3_logic_test.dart`.
- Ce qui est testé : marge nette (livraison, main propre, trop loin, prix max), état le plus bas,
  blocage d'un défaut majeur, tableau de bord du Stock, export CSV et rattachement des réponses.
- Lancés en CI avant le build.

### Consommation Gemini (estimation)
| Étape | Appels | Photos |
| --- | --- | --- |
| Pré-analyse Radar | 1 à 2 | non |
| Analyse complète | 3 à 4 (lecture, choix, vérification) | + 1 appel avec 6 photos max |
| Message vendeur | 1 | non |
| Propositions de réponse | 1 | non |

## Messages aux vendeurs

Onglet **Messages** (3e menu) :

- **Compte Leboncoin** : « Se connecter à Leboncoin » ouvre la page de connexion dans une
  WebView visible. Tu tapes toi-même tes identifiants ; l'appli ne lit ni n'enregistre jamais
  le mot de passe. Seuls les cookies de session sont gardés (comme dans un navigateur).
  L'indicateur affiche **Connecté / Non connecté**.
- **Envoi auto** : l'interrupteur général de l'envoi automatique. La carte affiche aussi le mode,
  le test à blanc, le compteur du jour et le bandeau « suspendu » avec le bouton **Réactiver**.
- **Liste des envois** : statut (en file, à confirmer, envoyé, test à blanc, échec, annulé),
  annonce, prix proposé, texte et date. Touche un envoi pour voir l'annonce, copier le texte,
  reprendre, annuler, ou le marquer comme envoyé.

**Message vendeur** (écran résultat ou notification) ouvre l'envoi en plein écran. La page
Leboncoin reste visible. La progression suit les étapes « Ouverture de l'annonce → Contact →
Message écrit → Envoyé ». Le bouton **STOP** arrête l'envoi à tout moment. L'annonce passe en
« Contacté » dans le fil Radar et sur l'écran résultat.

### Réglages (icône ⚙ de l'onglet)

- **Mode** : *toujours confirmer* (par défaut : l'appli écrit le message, tu appuies sur
  « Envoyer »), *envoi direct*, ou *automatique pour les bonnes affaires*.
- **Test à blanc** (activé par défaut) : l'appli fait tout sauf le clic final sur
  « Envoyer ». **Commence par là** et vérifie dans la liste que les essais finissent en
  « Test à blanc ».
- Ton (poli, amical, direct), vouvoiement ou tutoiement, proposition de prix (le prix conseillé
  quand il est sous le prix demandé), consignes perso. Gemini rédige chaque message à neuf, donc
  jamais deux fois le même texte. Si Gemini échoue, un modèle de texte tiré au hasard sert de repli.

### Mode automatique

Le radar envoie seul **uniquement si tout est réuni** :

- marge au-dessus du seuil ;
- verdict IA « oui » (garde-fou marque + vérification de correspondance, faite pendant l'analyse ; sans « oui », jamais d'envoi auto) ;
- aucune alerte (pièces, défaut, version incertaine) ;
- annonce jamais contactée ;
- prix connu.

Sinon, tu reçois une notification « À confirmer ». Après l'envoi : « Message envoyé à … (proposé
120 €) ».

### Comment l'envoi fonctionne

Les boutons sont trouvés par leur texte (« Envoyer un message », « Contacter », « Message »).
Une liste noire exclut tout bouton d'offre, de réservation, d'achat ou de paiement.

Le texte est écrit avec le setter natif, suivi des événements input et change. Le message n'est
marqué envoyé qu'après avoir été vu dans la conversation. Si une étape échoue, l'envoi s'arrête,
la page reste affichée, et le journal note l'étape, les boutons vus et un extrait de la page.

**Vérification anti-robot ou page de connexion** : l'envoi s'arrête aussitôt et tu reçois une
notification « Action requise ». L'appli ne la contourne jamais : c'est à toi de la faire.

### Garde-fous (codés en dur, seul le plafond est réglable)

- 10 messages automatiques par jour au plus (réglable jusqu'à 20) et 3 par heure ;
- au moins 3 min entre deux envois, plus 20 à 90 s au hasard, et 1 à 3 s entre les étapes ;
- aucun envoi automatique entre 22 h et 8 h : les messages sont mis en file pour 8 h ;
- un seul contact par annonce, et un seul par vendeur sur 24 h ;
- 2 échecs de suite ou une vérification anti-robot suspendent l'envoi auto jusqu'à ce que tu le
  réactives.

⚠️ Les conditions d'utilisation de Leboncoin peuvent interdire l'automatisation de la messagerie,
et des envois en série peuvent faire suspendre le compte. Garde des plafonds bas et préfère le
mode « toujours confirmer ».

## Acheter et revendre

- **Prix d'achat max** (écran résultat) : reprise MPB − ta marge mini, arrondi aux 5 € ; plus
  la version prudente (état juste en dessous) et le prix à proposer au vendeur.
- **Message vendeur** : message prêt (« toujours disponible ? Je vous propose X € ») copié,
  puis l'annonce s'ouvre ; il suffit de le coller dans la messagerie Leboncoin. Aussi via le
  bouton **Contacter** des notifications de bonnes affaires.
- **Mes affaires** (icône carton, onglet Analyse ; ou menu Radar) : « Je l'ai acheté » sur un
  résultat, puis « Marquer comme vendu » (prix, MPB / Leboncoin / eBay…). Bénéfice réalisé,
  bénéfice du mois, stock et sa reprise estimée, bénéfice moyen.
- **Pas le bon modèle ?** (carte d'un élément) : choisis le bon nom dans le catalogue MPB ;
  les prix de reprise réels sont recalculés et la correction est retenue pour les analyses
  suivantes (`lib/services/corrections.dart`).

## Clés et modèles Gemini
Dans `lib/secrets.dart` : modèle `gemini-flash-lite-latest` (repli automatique sur
`gemini-3.5-flash-lite` si l'alias est refusé) et clés API en dur (même compte). La première
clé est utilisée ; on passe à la suivante si elle est invalide ou à court de quota (429,
après une relance de 4 s). La clé qui marche est gardée pour la suite ; si toutes sont à
court de quota, un message clair s'affiche.

Pour le chat (`GeminiService.chat`) : texte libre, sans `responseSchema`, avec l'outil
`google_search`. Modèle `gemini-flash-lite-latest` partout (analyse, chat, messages) ;
si le modèle refuse l'outil, l'appel est refait sans outil. Un quota dépassé (429) affiche
un message clair.

**Garde le dépôt privé.** En offre gratuite, Google peut utiliser les textes envoyés.

## Obtenir l'APK

### Option A : GitHub, sans rien installer
1. Onglet **Actions** → « Build APK » → **Run workflow** (ou pousse sur `main`).
2. Après 5 à 8 minutes, télécharge l'artefact **mpb-check-apk** (un zip qui contient `app-release.apk`).
3. Installe-le sur ton téléphone (autorise « sources inconnues »).

Le workflow génère `android/` avec `flutter create`, complète le manifeste avec
`tool/patch_manifest.py` (permission INTERNET, nom « MPB Check », partage Android,
`singleTask`), génère l'icône (`flutter_launcher_icons`), puis lance `flutter analyze` et
`flutter build apk --release`.

> **Signature** : l'APK est signé avec la clé fixe de `signing/` (`mpb-check.jks`,
> mots de passe dans `key.properties`), branchée par `tool/patch_signing.py`. Chaque
> nouvelle version s'installe donc par-dessus la précédente, sans désinstaller (le numéro
> de build Android augmente à chaque run). Le workflow vérifie l'empreinte du certificat
> (SHA-256 `59:10:76:AC:…:81:73:47`). **Garde une copie de ce dossier** : sans cette clé,
> plus aucune mise à jour ne pourra s'installer par-dessus. Et garde le dépôt privé.

### Option B : sur ton PC avec Flutter
```bash
flutter create --org fr.eddybonnet --project-name mpb_check --platforms android .
python3 tool/patch_manifest.py
python3 tool/patch_signing.py
python3 tool/patch_radar.py android
flutter pub get
dart run flutter_launcher_icons
flutter build apk --release
```
L'APK est dans `build/app/outputs/flutter-apk/`.

## Fichiers
- `lib/services/leboncoin_reader.dart` : lecture de la page (testé sur la structure réelle le 09/10/2026)
- `lib/services/mpb_web_transport.dart` : requêtes MPB depuis une WebView mpb.com
- `lib/services/local_identifier.dart` : identification de secours sans IA
- `lib/services/match_check.dart` : garde-fou marque + verdict IA oui/doute/non
- `lib/screens/export_pdf.dart`, `assets/fonts/` : export PDF (police Roboto, Apache 2.0)
- `lib/services/mpb_catalog.dart`, `lib/screens/catalog_screen.dart` : catalogue local des noms exacts MPB et son écran
- `lib/services/mpb_service.dart` : API JSON de MPB (suggestions, annonces en vente, identifiant et prix de reprise réels)
- `lib/services/gemini_service.dart` : appels Gemini (JSON imposé pour l'analyse, chat avec recherche)
- `lib/services/analyzer.dart` : enchaînement complet de l'analyse
- `lib/services/history.dart` : historique local (50 analyses + conversations)
- `lib/screens/` : accueil, analyse, résultat, questions, réglages
- `lib/messages/`, `lib/screens/messages_screen.dart`, `send_screen.dart` : messages aux vendeurs (rédaction, automate, garde-fous)
- `lib/theme.dart`, `lib/widgets/common.dart` : thème et composants
- `assets/icon/` : icône de l'appli
- `tool/patch_manifest.py` : ajouts au manifeste Android
- `tool/patch_signing.py`, `signing/` : signature fixe de l'APK
- `android_native/proguard-rules.pro` : règles R8 (WorkManager/Room, radar) ; sans elles
  l'appli plante au démarrage en release


## IA gratuite : DeepSeek (chat web) + Gemini

- `lib/services/deepseek_web.dart` pilote **https://chat.deepseek.com/** (pas le site vitrine) dans une WebView invisible ; session partagée avec la WebView visible. Si le site change : corriger uniquement `DsSite` en tête du fichier.
- **Paramètres** (icône engrenage de l'accueil) : tous les réglages regroupés — seuil « bonne affaire », marge nette, DeepSeek (connexion, interrupteurs, tests texte et vision), clés Gemini, Leboncoin, radar, messages, catalogue, calcul de secours, thème.
- `GeminiService.generateJson` : DeepSeek d'abord pour le texte, Gemini en repli. Photos : DeepSeek seulement si l'option est cochée **et** si le test de vision a réussi ; sinon Gemini.
- Chat « Questions » : choix DeepSeek (conversation gardée ouverte, photos jointes en option) ou Gemini + recherche web ; repli automatique sur Gemini.
- Radar → Toutes les annonces : appui long pour sélectionner et supprimer, menu ⋮ → « Tout supprimer… » (avec option d'oublier aussi les annonces vues).
- En cas de panne durable (session expirée, anti-robot), DeepSeek est suspendu 10 min et Gemini prend le relais.
