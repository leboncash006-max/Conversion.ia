import 'dart:math';

import 'models.dart';

// ============================================================
//  Scénarios d'appels (1/2) : feux, secours à personne, routes
// ============================================================

void person(Incident c, Random r, {bool? female}) {
  final f = female ?? r.nextBool();
  c.v['af'] = f;
  c.v['anom'] = '${f ? 'Mme' : 'M.'} ${pick(r, noms)}';
}

void victim(Incident c, Random r, {bool? female, int min = 20, int max = 85}) {
  final f = female ?? r.nextBool();
  c.v['vf'] = f;
  c.v['prenom'] = pick(r, f ? prenomsF : prenomsH);
  c.v['age'] = min + r.nextInt(max - min + 1);
}

String an(Incident c) => c.v['anom'] as String;
String fe(Incident c) => c.v['af'] == true ? 'e' : '';
bool yes(Incident c, String k) => c.v[k] == true;

String etg(int e) => e == 0 ? 'rez-de-chaussée' : (e == 1 ? '1er étage' : '${e}e étage');

String deLa(String s) {
  if (RegExp(r'^[aeiouéèh]', caseSensitive: false).hasMatch(s)) return "de l'$s";
  if (s.startsWith('boulevard') || s.startsWith('chemin')) return 'du $s';
  return 'de la $s';
}

Q adresse([String Function(Incident c)? custom]) =>
    Q('adresse', "Quelle est l'adresse exacte ?", custom ?? (c) => "C'est au ${c.address} ! Faites vite !");

Map<VType, int> needsOf(Map<VType, int> m) => {
  for (final e in m.entries)
    if (e.value > 0) e.key: e.value,
};

List<Scenario> scenariosA() => [
  // ---------------------------------------------- Feu de cuisine
  Scenario(
    id: 'feu_cuisine',
    nature: Nature.feuCuisine,
    zone: Zone.ville,
    weight: 1.2,
    target: 12,
    work: 15,
    setup: (c, r) {
      person(c, r);
      c.v['type'] = pick(r, ['friteuse', "casserole d'huile", 'poêle']);
      c.v['etage'] = r.nextInt(5);
    },
    caller: (c) => '${an(c)} · paniqué${fe(c)}',
    opening: (c) => ["Allô ?! Il y a le feu dans ma cuisine ! Ma ${c.v['type']} a pris feu !"],
    questions: [
      adresse(),
      Q(
        'flammes',
        'Les flammes touchent-elles les murs, les placards ?',
        (c) => yes(c, 'escalade')
            ? "OUI ! ÇA A EXPLOSÉ, LES PLACARDS BRÛLENT !"
            : "Non, c'est que dans la ${c.v['type']}… mais ça monte haut !",
      ),
      Q(
        'blesse',
        "Êtes-vous blessé ? Quelqu'un est brûlé ?",
        (c) => yes(c, 'escalade') ? "J'ai le bras brûlé… ça fait super mal…" : "Non, non, personne n'est brûlé.",
      ),
      Q(
        'etage',
        'À quel étage êtes-vous ?',
        (c) => (c.v['etage'] as int) == 0 ? "Rez-de-chaussée, c'est une maison." : "Au ${etg(c.v['etage'] as int)}.",
      ),
    ],
    advice: [
      Advice(
        'couvercle',
        "Coupez le feu et posez un couvercle ou un linge mouillé essoré dessus. Surtout pas d'eau !",
        (c) => yes(c, 'escalade') ? "C'est trop tard, tout brûle !!" : "Voilà… j'ai mis le couvercle… ça s'étouffe !",
        1,
        apply: (c) {
          if (!yes(c, 'escalade')) c.v['maitrise'] = true;
        },
      ),
      Advice(
        'eau',
        "Jetez un seau d'eau dessus, vite !",
        (c) => "…AAAH ! Une boule de feu ! Tout brûle ! Mon bras !!",
        -2,
        apply: (c) => c.v['escalade'] = true,
      ),
      Advice(
        'sortir',
        'Si ça ne s\'éteint pas, sortez, fermez la porte de la cuisine et attendez-nous dehors.',
        (c) => "D'accord, je sors et je ferme derrière moi.",
        1,
      ),
    ],
    needs: (c) => yes(c, 'escalade') ? {VType.fpt: 1, VType.vsav: 1} : {VType.fpt: 1},
    ambiance: (c) => yes(c, 'escalade')
        ? "Feu de cuisine propagé, une victime brûlée au bras. On attaque."
        : yes(c, 'maitrise')
        ? "Feu étouffé par l'occupant, on contrôle la hotte et on ventile."
        : "Feu de ${c.v['type']} en cours, on attaque à l'extincteur.",
    report: (c, good) => yes(c, 'escalade')
        ? "Feu éteint. Cuisine détruite, victime brûlée au 2e degré prise en charge."
        : "Feu éteint, logement ventilé. Plus de peur que de mal.",
  ),

  // ---------------------------------------------- Feu d'appartement
  Scenario(
    id: 'feu_appart',
    nature: Nature.feuHabitation,
    zone: Zone.centre,
    weight: 1.1,
    target: 10,
    work: 35,
    setup: (c, r) {
      person(c, r);
      c.v['etage'] = 1 + r.nextInt(8);
      c.v['bloque'] = r.nextDouble() < 0.6;
      c.v['critique'] = c.v['bloque'];
    },
    caller: (c) => '${an(c)} · voisin${fe(c)}, affolé${fe(c)}',
    opening: (c) => ["Il y a de la fumée noire qui sort de chez mes voisins ! Ça sent le brûlé dans tout l'immeuble !"],
    questions: [
      adresse(),
      Q('etage', "À quel étage est l'appartement en feu ?", (c) => "Au ${etg(c.v['etage'] as int)} !"),
      Q(
        'dedans',
        "Y a-t-il quelqu'un à l'intérieur ?",
        (c) => yes(c, 'bloque')
            ? "Je crois que oui… la dame est âgée, elle sort jamais… j'entends crier !"
            : "Je pense pas, ils sont partis en voiture ce matin.",
      ),
      Q(
        'escalier',
        "La cage d'escalier est-elle enfumée ?",
        (c) => (c.v['etage'] as int) >= 3 ? "Oui, on voit plus rien dans l'escalier !" : "Un peu, ça commence.",
      ),
      Q(
        'vous',
        'Où êtes-vous en ce moment ?',
        (c) => "Chez moi, au ${etg((c.v['etage'] as int) + 1)}, juste au-dessus !",
      ),
    ],
    advice: [
      Advice(
        'confine',
        'Restez chez vous, fermez la porte, mettez des linges mouillés en bas et allez à la fenêtre pour qu\'on vous voie.',
        (c) => "D'accord… je mets des serviettes… je suis à la fenêtre.",
        1,
      ),
      Advice(
        'ascenseur',
        "Prenez l'ascenseur et descendez vite !",
        (c) => "L'ascenseur… il s'est bloqué entre deux étages ! La fumée rentre !!",
        -2,
        apply: (c) {
          c.v['appelant'] = true;
          c.v['critique'] = true;
        },
      ),
      Advice(
        'voisin',
        'Allez frapper chez la voisine pour la faire sortir.',
        (c) => "J'y vais… *tousse* … je vois rien… *tousse* *tousse*…",
        -1,
        apply: (c) => c.v['appelant'] = true,
      ),
    ],
    needs: (c) => needsOf({
      VType.fpt: 1,
      VType.epa: (c.v['etage'] as int) >= 3 || yes(c, 'bloque') ? 1 : 0,
      VType.vsav: yes(c, 'bloque') || yes(c, 'appelant') ? 1 : 0,
    }),
    ambiance: (c) =>
        "Feu d'appartement au ${etg(c.v['etage'] as int)}, fumées épaisses"
        "${yes(c, 'bloque') ? ", une victime à l'intérieur, on engage un binôme sous ARI" : ', on attaque'}.",
    report: (c, good) => good
        ? (yes(c, 'bloque')
              ? "Feu éteint. Victime sortie par l'échelle, intoxiquée mais consciente, transportée au CH."
              : "Feu éteint, appartement détruit, aucune victime.")
        : (yes(c, 'bloque')
              ? "Feu éteint… victime retrouvée inconsciente. Décédée malgré les soins."
              : "Feu éteint mais propagé aux appartements voisins. Gros dégâts."),
  ),

  // ---------------------------------------------- Malaise
  Scenario(
    id: 'malaise',
    nature: Nature.malaise,
    zone: Zone.ville,
    weight: 1.4,
    target: 15,
    work: 20,
    setup: (c, r) {
      person(c, r);
      victim(c, r, min: 58, max: 90);
      c.v['diabete'] = r.nextBool();
      c.v['coeur'] = !yes(c, 'diabete') && r.nextBool();
      c.v['critique'] = c.v['coeur'];
      c.v['lien'] = c.vf ? 'ma mère' : 'mon père';
    },
    caller: (c) => '${an(c)} · inquiet${fe(c)}',
    opening: (c) => [
      "Allô, c'est pour ${c.v['lien']}… ${c.g('il', 'elle')} a fait un malaise, ${c.g('il', 'elle')} est toute pâle…",
    ],
    questions: [
      adresse(),
      Q(
        'conscient',
        'La personne vous répond-elle quand vous lui parlez ?',
        (c) => "Oui, mais ${c.g('il', 'elle')} est un peu dans les vapes.",
      ),
      Q('respire', 'La personne respire-t-elle normalement ?', (c) => "Oui oui, ${c.g('il', 'elle')} respire."),
      Q('age', 'Quel âge a la personne ?', (c) => "${c.v['age']} ans."),
      Q(
        'traitement',
        'La personne a-t-elle des problèmes de santé, un traitement ?',
        (c) => yes(c, 'diabete')
            ? "${c.g('Il', 'Elle')} est diabétique… ${c.g('il', 'elle')} n'a pas mangé de la journée."
            : "${c.g('Il', 'Elle')} a de la tension, des médicaments pour le cœur.",
      ),
      Q(
        'poitrine',
        'Se plaint-elle d\'une douleur dans la poitrine ?',
        (c) => yes(c, 'coeur')
            ? "${c.g('Il', 'Elle')} dit que ça serre… et que ça descend dans le bras gauche."
            : 'Non, pas du tout.',
      ),
    ],
    advice: [
      Advice(
        'allonger',
        'Allongez la personne, desserrez ses vêtements et restez à côté.',
        (c) => "C'est fait, ${c.g('il', 'elle')} est allongé${c.vf ? 'e' : ''} sur le canapé.",
        1,
      ),
      Advice(
        'sucre',
        'Donnez-lui un peu de sucre ou un jus de fruit.',
        (c) => yes(c, 'diabete')
            ? "${c.g('Il', 'Elle')} a bu un jus d'orange… ${c.g('il', 'elle')} reprend des couleurs !"
            : "${c.g('Il', 'Elle')} a bu un peu… ${c.g('il', 'elle')} dit avoir la nausée.",
        0,
        apply: (c) => c.adviceScore += yes(c, 'diabete') ? 1 : -1,
      ),
      Advice(
        'marcher',
        'Faites-la marcher un peu pour la réveiller.',
        (c) =>
            "${c.g('Il', 'Elle')} s'est levé${c.vf ? 'e' : ''}… oh ! ${c.g('Il', 'Elle')} est retombé${c.vf ? 'e' : ''} !",
        -1,
      ),
    ],
    needs: (c) => needsOf({VType.vsav: 1, VType.smur: yes(c, 'coeur') ? 1 : 0}),
    ambiance: (c) => yes(c, 'diabete')
        ? 'Victime consciente, glycémie à 0,45. On re-sucre.'
        : yes(c, 'coeur')
        ? 'Douleur thoracique, ECG en cours. On attend le SMUR.'
        : 'Victime consciente, bilan en cours.',
    report: (c, good) => good
        ? 'Bilan passé, victime transportée au CH, état stable.'
        : (yes(c, 'coeur')
              ? 'Victime en arrêt à notre arrivée… réanimation sans succès.'
              : 'Victime transportée au CH, prise en charge tardive.'),
  ),

  // ---------------------------------------------- Arrêt cardiaque
  Scenario(
    id: 'acr',
    nature: Nature.acr,
    zone: Zone.ville,
    weight: 0.9,
    target: 9,
    work: 30,
    critical: true,
    setup: (c, r) {
      person(c, r);
      victim(c, r, female: !(c.v['af'] as bool), min: 52, max: 82);
      c.v['dae'] = r.nextDouble() < 0.45;
    },
    caller: (c) => '${an(c)} · en panique totale',
    opening: (c) => [
      "AU SECOURS ! ${c.vf ? 'Ma femme' : 'Mon mari'}… ${c.g('il', 'elle')} s'est effondré${c.vf ? 'e' : ''} d'un coup… ${c.g('il', 'elle')} bouge plus !!",
    ],
    questions: [
      adresse(),
      Q(
        'respire',
        'Regardez son ventre : est-ce qu\'il se soulève ? Respire-t-elle ?',
        (c) => "Je… non… je crois pas… ${c.g('il', 'elle')} fait des bruits bizarres, comme des ronflements…",
      ),
      Q(
        'conscient',
        "Réagit-elle si vous lui parlez fort et lui pincez l'épaule ?",
        (c) => "Non ! Rien ! ${c.g('Il', 'Elle')} réagit pas !",
      ),
      Q(
        'dae',
        'Y a-t-il un défibrillateur à proximité ? Pharmacie, mairie, salle de sport ?',
        (c) => yes(c, 'dae') ? "Euh… oui ! Il y en a un à la pharmacie en bas !" : 'Je sais pas… je crois pas…',
      ),
      Q(
        'seul',
        "Y a-t-il quelqu'un d'autre avec vous ?",
        (c) => yes(c, 'dae') ? 'Mon fils est là !' : 'Oui, je suis tout seul${fe(c)}…',
      ),
    ],
    advice: [
      Advice(
        'mce',
        'Je vais vous guider. Mettez la personne sur le dos, au sol. Mains au centre de la poitrine, bras tendus, appuyez fort et vite. Comptez avec moi : 1, 2, 3…',
        (c) => "D'accord… 1, 2, 3, 4… *souffle*… 15, 16… je continue !",
        1,
        apply: (c) => c.v['mce'] = true,
      ),
      Advice(
        'dae_go',
        "Envoyez votre fils chercher le défibrillateur. Allumez-le et suivez ce qu'il dit.",
        (c) =>
            "Il revient ! L'appareil parle… « choc délivré »… ${c.g('il', 'elle')}… ${c.g('il', 'elle')} respire un peu !!",
        1,
        after: 'dae',
        when: (c) => yes(c, 'dae'),
        apply: (c) => c.v['daeOk'] = true,
      ),
      Advice(
        'eau',
        "Mettez-lui de l'eau fraîche sur le visage, attendez qu'il se réveille.",
        (c) => "Ça marche pas !! ${c.g('Il', 'Elle')} se réveille pas !!",
        -1,
      ),
      Advice(
        'pls',
        'Mettez la personne en position latérale de sécurité.',
        (c) => "Voilà, ${c.g('il', 'elle')} est sur le côté… ${c.g('il', 'elle')} fait toujours ces bruits…",
        -1,
      ),
    ],
    needs: (c) => {VType.vsav: 1, VType.smur: 1},
    ambiance: (c) => yes(c, 'mce')
        ? 'ACR, massage cardiaque en cours par la famille. On prend le relais, DAE posé.'
        : 'Victime en arrêt cardio-respiratoire, aucun massage en cours. On débute la RCP.',
    report: (c, good) => good
        ? "Reprise d'activité cardiaque ! Victime transportée au CH avec le SMUR."
        : 'Malgré la réanimation, décès constaté par le médecin du SMUR.',
  ),

  // ---------------------------------------------- Chute
  Scenario(
    id: 'chute',
    nature: Nature.blesse,
    zone: Zone.ville,
    weight: 1.2,
    target: 18,
    work: 20,
    setup: (c, r) {
      person(c, r);
      c.v['echelle'] = r.nextBool();
      victim(c, r, female: yes(c, 'echelle') ? false : true, min: 35, max: 88);
    },
    caller: (c) => '${an(c)} · ${yes(c, 'echelle') ? 'collègue' : 'voisin${fe(c)}'}',
    opening: (c) => [
      yes(c, 'echelle')
          ? "Mon collègue est tombé de l'échelle en taillant la haie ! Il a mal au dos !"
          : "Bonsoir… c'est ma voisine, elle est tombée dans l'escalier, elle arrive plus à se relever…",
    ],
    questions: [
      adresse(),
      Q(
        'conscient',
        'La victime est-elle consciente ?',
        (c) => yes(c, 'echelle') ? 'Oui, il me parle.' : 'Oui, elle me parle, elle a toute sa tête.',
      ),
      Q(
        'douleur',
        'Où a-t-elle mal exactement ?',
        (c) => yes(c, 'echelle')
            ? "Au dos… et il dit qu'il a des fourmis dans les jambes…"
            : 'À la hanche… sa jambe est tournée bizarrement.',
      ),
      Q(
        'hauteur',
        'De quelle hauteur est-il tombé ?',
        (c) => 'Je dirais trois mètres…',
        when: (c) => yes(c, 'echelle'),
      ),
    ],
    advice: [
      Advice(
        'bouger_pas',
        'Ne la bougez surtout pas, couvrez-la et parlez-lui en attendant.',
        (c) => "D'accord, je reste à côté et je lui parle.",
        1,
      ),
      Advice(
        'relever',
        'Aidez-la à se relever et asseyez-la sur une chaise.',
        (c) => yes(c, 'echelle')
            ? 'Il a essayé… il sent plus du tout ses jambes maintenant !!'
            : "AÏE ! Elle a hurlé… on l'a reposée par terre…",
        -2,
        apply: (c) => c.v['aggrave'] = true,
      ),
      Advice('boire', "Donnez-lui un verre d'eau.", (c) => "D'accord, elle a bu un peu.", -1),
    ],
    needs: (c) => {VType.vsav: 1},
    ambiance: (c) => yes(c, 'echelle')
        ? 'Chute de 3 mètres, suspicion de trauma rachidien. Immobilisation complète.'
        : 'Chute dans l\'escalier, suspicion de fracture du col du fémur.',
    report: (c, good) => good && !yes(c, 'aggrave')
        ? 'Victime immobilisée et transportée au CH. RAS.'
        : 'Victime transportée au CH. Lésions aggravées par la mobilisation.',
  ),

  // ---------------------------------------------- Accident en ville
  Scenario(
    id: 'avp_ville',
    nature: Nature.avp,
    zone: Zone.ville,
    weight: 1.1,
    target: 12,
    work: 25,
    setup: (c, r) {
      person(c, r);
      c.v['scooter'] = r.nextBool();
      c.v['inconscient'] = r.nextBool();
      c.v['critique'] = c.v['inconscient'];
      victim(c, r, female: yes(c, 'scooter') ? false : true, min: 17, max: 80);
      c.v['rue2'] = pick(r, rues);
    },
    caller: (c) => '${an(c)} · témoin',
    opening: (c) => [
      yes(c, 'scooter')
          ? "Il y a un accident ! Une voiture a percuté un scooter, le gars est par terre !"
          : "Une voiture vient de renverser une dame sur le passage piéton !",
    ],
    questions: [
      adresse(
        (c) => "À l'angle ${deLa(c.address.replaceAll(RegExp(r'^\d+ '), ''))} et ${deLa(c.v['rue2'] as String)} !",
      ),
      Q(
        'conscient',
        'La victime est-elle consciente ?',
        (c) => yes(c, 'inconscient')
            ? 'Non… elle bouge pas… mais elle respire.'
            : 'Elle gémit… elle dit qu\'elle a mal à la jambe.',
      ),
      Q(
        'combien',
        'Combien de victimes ? Et le conducteur ?',
        (c) => 'Le conducteur va bien, il est sous le choc. Juste une victime.',
      ),
      Q(
        'danger',
        "Y a-t-il de la fumée, une fuite d'essence, quelqu'un de coincé ?",
        (c) => 'Non, rien de tout ça. Personne de coincé.',
      ),
      Q(
        'circulation',
        'La circulation est-elle bloquée ?',
        (c) => 'Oui, ça klaxonne de partout, les gens s\'énervent…',
      ),
    ],
    advice: [
      Advice(
        'casque',
        'Ne lui retirez surtout pas son casque et ne le bougez pas.',
        (c) => "OK, personne n'y touche.",
        1,
        when: (c) => yes(c, 'scooter'),
      ),
      Advice(
        'retirer',
        'Retirez-lui son casque pour qu\'il respire mieux.',
        (c) => "C'est fait… oh non… il saigne de la tête…",
        -2,
        when: (c) => yes(c, 'scooter'),
        apply: (c) => c.v['aggrave'] = true,
      ),
      Advice(
        'baliser',
        'Mettez-vous en sécurité, allumez vos feux de détresse, faites ralentir les voitures.',
        (c) => "D'accord, j'ai mis mes warnings.",
        1,
      ),
      Advice(
        'deplacer',
        'Tirez la victime sur le trottoir pour la mettre à l\'abri.',
        (c) => 'On l\'a tirée… elle a crié très fort…',
        -1,
      ),
    ],
    needs: (c) => needsOf({VType.vsav: 1, VType.police: 1, VType.smur: yes(c, 'inconscient') ? 1 : 0}),
    ambiance: (c) => yes(c, 'inconscient')
        ? 'Une victime inconsciente, pas de désincarcération. On attend le SMUR.'
        : 'Une victime consciente, trauma de jambe. Pas de désincarcération.',
    report: (c, good) => good
        ? 'Victime prise en charge et transportée au CH. Police sur place pour le constat.'
        : 'Victime transportée en urgence absolue. Pronostic vital engagé.',
  ),

  // ---------------------------------------------- Accident autoroute
  Scenario(
    id: 'avp_autoroute',
    nature: Nature.avp,
    zone: Zone.autoroute,
    minLevel: 1,
    weight: 0.8,
    target: 15,
    work: 40,
    critical: true,
    setup: (c, r) {
      person(c, r);
      c.v['fumee'] = r.nextDouble() < 0.4;
      c.v['victimes'] = 2;
    },
    caller: (c) => '${an(c)} · automobiliste',
    opening: (c) => [
      "Accident sur l'autoroute ! Une voiture a fait des tonneaux, elle est sur le toit ! Il y a des gens coincés dedans !",
    ],
    questions: [
      adresse((c) => "A71, direction Paris, juste après la sortie 12 ! Je suis sur la bande d'arrêt d'urgence."),
      Q(
        'combien',
        'Combien de personnes dans la voiture ?',
        (c) => 'Deux ! Le conducteur crie, la passagère ne bouge pas…',
      ),
      Q('coince', 'Peuvent-elles sortir seules ?', (c) => 'Non, les portes sont écrasées, ils sont coincés !'),
      Q(
        'fumee',
        "Le véhicule fume-t-il ? Ça sent l'essence ?",
        (c) => yes(c, 'fumee') ? "Oui, ça fume du moteur ! Ça sent l'essence !" : 'Non, pas de fumée.',
      ),
      Q('vous', 'Êtes-vous en sécurité ?', (c) => 'Je suis derrière la glissière.'),
    ],
    advice: [
      Advice(
        'glissiere',
        "Restez derrière la glissière, ne traversez pas les voies, n'essayez pas de les sortir.",
        (c) => "D'accord, je reste là.",
        1,
      ),
      Advice(
        'sortir',
        'Essayez de sortir les victimes de la voiture.',
        (c) => "J'arrive pas à ouvrir… je me suis coupé sur le verre…",
        -1,
        apply: (c) => c.v['aggrave'] = true,
      ),
      Advice(
        'triangle',
        'Allez poser votre triangle sur la voie pour prévenir les autres.',
        (c) => "J'y vais… WOAH, un camion m'a frôlé !",
        -1,
      ),
    ],
    needs: (c) =>
        needsOf({VType.vsr: 1, VType.vsav: 2, VType.fpt: yes(c, 'fumee') ? 1 : 0, VType.smur: 1, VType.police: 1}),
    ambiance: (c) =>
        'Véhicule sur le toit, deux victimes incarcérées${yes(c, 'fumee') ? ', départ de feu moteur' : ''}. On désincarcère.',
    report: (c, good) => good
        ? 'Deux victimes désincarcérées, prises en charge par le SMUR et transportées au CH. Bon boulot.'
        : 'Désincarcération trop tardive… la passagère est décédée sur place.',
  ),

  // ---------------------------------------------- Noyade
  Scenario(
    id: 'noyade',
    nature: Nature.noyade,
    zone: Zone.riviere,
    minLevel: 1,
    weight: 0.7,
    target: 12,
    work: 30,
    critical: true,
    setup: (c, r) {
      person(c, r);
      c.v['enfant'] = r.nextBool();
      victim(c, r, female: false, min: 7, max: 9);
    },
    caller: (c) => '${an(c)} · promeneur${c.v['af'] == true ? 'se' : ''}',
    opening: (c) => ["Vite ! Quelqu'un est tombé dans la Loire, près du pont ! Il se débat dans l'eau !"],
    questions: [
      adresse((c) => 'Quai des Mariniers, juste à côté du pont Wilson !'),
      Q(
        'qui',
        "Qui est dans l'eau ? Un adulte, un enfant ?",
        (c) => yes(c, 'enfant')
            ? 'Un enfant ! Un petit garçon, 8 ans peut-être !'
            : "Un homme, il avait l'air d'avoir bu…",
      ),
      Q('voit', 'Vous le voyez encore ?', (c) => 'Oui… il est emporté par le courant… il s\'accroche à une branche !'),
      Q('bouee', 'Y a-t-il une bouée de sauvetage près de vous ?', (c) => 'Oui, il y en a une accrochée au poteau !'),
    ],
    advice: [
      Advice(
        'lancer',
        'Lancez-lui la bouée en gardant la corde. Ne sautez pas à l\'eau.',
        (c) => "Je l'ai lancée… IL L'A ATTRAPÉE ! Il s'accroche !",
        1,
        after: 'bouee',
        apply: (c) => c.v['bouee'] = true,
      ),
      Advice(
        'sauter',
        'Sautez pour aller le chercher !',
        (c) => "J'y vais… *plouf*… *grésillements*…",
        -2,
        apply: (c) {
          c.v['sauteur'] = true;
          c.v['coupe'] = true;
        },
      ),
      Advice(
        'suivre',
        'Suivez-le des yeux le long de la berge et guidez les secours à leur arrivée.',
        (c) => 'Je le suis, je ne le lâche pas des yeux !',
        1,
      ),
    ],
    needs: (c) => {VType.bls: 1, VType.vsav: yes(c, 'sauteur') ? 2 : 1, VType.smur: 1},
    ambiance: (c) => yes(c, 'bouee')
        ? 'Victime accrochée à une bouée, on met le bateau à l\'eau.'
        : 'Victime plus visible en surface, on engage les plongeurs.',
    report: (c, good) => good
        ? 'Victime sortie de l\'eau, hypothermie, transportée au CH. Elle va s\'en sortir.'
        : 'Victime retrouvée par les plongeurs… trop tard. Décès.',
  ),

  // ---------------------------------------------- Monoxyde de carbone
  Scenario(
    id: 'intox_co',
    nature: Nature.intoxication,
    zone: Zone.ville,
    minLevel: 1,
    weight: 0.8,
    target: 15,
    work: 30,
    critical: true,
    setup: (c, r) {
      person(c, r);
      c.v['victimes'] = 3;
    },
    caller: (c) => '${an(c)} · fatigué${fe(c)}, confus${c.v['af'] == true ? 'e' : ''}',
    opening: (c) => [
      "Bonsoir… euh, je sais pas si j'appelle au bon endroit… toute la famille a mal à la tête, mon fils a vomi… on a peut-être mangé un truc pas frais ?",
    ],
    questions: [
      adresse(),
      Q(
        'combien',
        'Combien de personnes ont des symptômes ?',
        (c) => 'Nous trois… même le chien est bizarre, il dort tout le temps.',
      ),
      Q(
        'chauffage',
        'Comment chauffez-vous votre logement ?',
        (c) => 'Avec un vieux poêle… on l\'a rallumé aujourd\'hui, il fait froid.',
      ),
      Q(
        'conscient',
        'Tout le monde est-il conscient ?',
        (c) => 'Oui… mais ma fille est très endormie… elle a du mal à parler.',
      ),
    ],
    advice: [
      Advice(
        'aerer',
        'Ouvrez les fenêtres, éteignez le poêle et sortez tous dehors, maintenant.',
        (c) => "On sort… l'air frais fait du bien… ma fille arrive à marcher.",
        1,
        apply: (c) => c.v['sortis'] = true,
      ),
      Advice(
        'dormir',
        'Allongez-vous et reposez-vous, ça va passer.',
        (c) => "D'accord… on va se coucher… *bâillement*…",
        -2,
        apply: (c) => c.v['aggrave'] = true,
      ),
    ],
    needs: (c) => needsOf({VType.fpt: 1, VType.vsav: 1, VType.smur: yes(c, 'aggrave') ? 1 : 0}),
    ambiance: (c) => yes(c, 'sortis')
        ? 'Famille dehors. CO à 450 ppm dans le logement ! On ventile, 3 victimes.'
        : 'Détecteur CO en alarme dès l\'entrée, 3 victimes somnolentes. On évacue.',
    report: (c, good) => good
        ? 'Trois victimes intoxiquées au CO transportées au CH. Le poêle est condamné.'
        : 'Intoxication grave au monoxyde de carbone. Une victime n\'a pas survécu.',
  ),

  // ---------------------------------------------- Fuite de gaz
  Scenario(
    id: 'gaz',
    nature: Nature.fuiteGaz,
    zone: Zone.centre,
    weight: 0.8,
    target: 15,
    work: 25,
    setup: (c, r) => person(c, r),
    caller: (c) => '${an(c)} · résident${fe(c)}',
    opening: (c) => ["Ça sent super fort le gaz dans la cage d'escalier, ça pique le nez…"],
    questions: [
      adresse(),
      Q(
        'ou',
        "D'où vient l'odeur ? D'un appartement en particulier ?",
        (c) => 'Je crois de chez le voisin du 2e, il répond pas.',
      ),
      Q('combien', "Combien de logements dans l'immeuble ?", (c) => 'Une douzaine…'),
      Q('vous', "Êtes-vous dans l'immeuble ?", (c) => 'Oui, sur le palier.'),
    ],
    advice: [
      Advice(
        'pas_toucher',
        "N'allumez rien, ne touchez à aucun interrupteur, ne sonnez pas. Sortez et éloignez les gens.",
        (c) => "D'accord, je sors et je préviens les gens en frappant aux portes.",
        1,
      ),
      Advice(
        'briquet',
        "Repérez d'où ça vient avec un briquet.",
        (c) => 'Un briq… attendez… *BOUM*',
        -2,
        apply: (c) {
          c.v['explosion'] = true;
          c.v['critique'] = true;
          c.v['coupe'] = true;
        },
      ),
      Advice('sonner', 'Sonnez chez le voisin pour le prévenir.', (c) => 'Je sonne… il répond pas…', -1),
    ],
    needs: (c) => yes(c, 'explosion') ? {VType.fpt: 2, VType.epa: 1, VType.vsav: 2, VType.smur: 1} : {VType.fpt: 1},
    ambiance: (c) => yes(c, 'explosion')
        ? 'EXPLOSION de gaz, façade en partie effondrée, plusieurs victimes ! On a besoin de monde !'
        : 'Forte odeur de gaz. On coupe le compteur, on évacue l\'immeuble.',
    report: (c, good) => yes(c, 'explosion')
        ? (good
              ? 'Explosion maîtrisée. Deux victimes extraites et transportées au CH.'
              : 'Bilan lourd après l\'explosion : un décès, plusieurs blessés.')
        : 'Fuite sur un raccord, gaz coupé, immeuble ventilé. Personne de blessé.',
  ),
];
