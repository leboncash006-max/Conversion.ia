# Allô 18

Jeu Android (Flutter) : tu es opérateur au centre de traitement de l'alerte des pompiers.

- **Le 18 sonne** : décroche avant que l'appelant ne raccroche.
- **Pose les bonnes questions** : adresse, étage, victimes, personne coincée… Chaque appelant a son caractère.
- **Engage les moyens** sur la carte de la ville (VSAV, FPT, échelle, désincarcération, feux de forêt, bateau, SMUR, police) et suis-les en temps réel.
- **Conseille en direct** : massage cardiaque, couvercle sur la friteuse… un mauvais conseil peut tout faire basculer.
- **Méfie-toi** des canulars, des appels pour le 17 ou le 15, et des appels qui ressemblent à des blagues mais n'en sont pas.
- **Débrief** en fin de garde, score, vies sauvées, et montée en grade de stagiaire à officier CODIS.

## Code

| Fichier | Rôle |
| --- | --- |
| `lib/main.dart` | Accueil, profil sauvegardé, débrief |
| `lib/game_screen.dart` | Écran de garde : appel, sonnerie, radio |
| `lib/sheets.dart` | Engagement des moyens, fiche d'intervention |
| `lib/map_view.dart` | Carte de la ville |
| `lib/sim.dart` | Moteur : appels, véhicules, renforts, notation |
| `lib/scenarios_a.dart`, `lib/scenarios_b.dart` | Les 21 types d'appels |
| `lib/models.dart` | Véhicules, natures, profil, grades |
| `test/allo18_test.dart` | Gardes complètes jouées par un robot |

## APK

Le workflow `Build APK` (push sur `main` ou lancement manuel) crée le projet Flutter, lance les tests, compile l'APK et le publie dans une release GitHub (`Allo18.apk`).
