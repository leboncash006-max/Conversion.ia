import 'models.dart';
import 'scenarios_a.dart';

// ============================================================
//  Scénarios d'appels (2/2) : feux spéciaux, opérations
//  diverses, canulars et appels hors compétence
// ============================================================

List<Scenario> scenariosB() => [
  // ---------------------------------------------- Feu de forêt
  Scenario(
    id: 'feu_foret',
    nature: Nature.feuForet,
    zone: Zone.foret,
    weight: 0.8,
    target: 15,
    work: 45,
    setup: (c, r) {
      person(c, r);
      c.v['vent'] = r.nextBool();
      c.v['maisons'] = r.nextBool();
    },
    caller: (c) => '${an(c)} · randonneur${c.v['af'] == true ? 'se' : ''}',
    opening: (c) => ["Allô, il y a de la fumée dans le bois de Vauclair ! On voit des flammes entre les arbres !"],
    questions: [
      adresse((c) => 'Bois de Vauclair, sur la route forestière, vers le parking du Grand Chêne !'),
      Q('taille', 'Quelle surface semble brûler ?', (c) => 'Comme un terrain de foot… et ça grossit !'),
      Q(
        'vent',
        'Y a-t-il du vent ? Où part la fumée ?',
        (c) => yes(c, 'vent')
            ? 'Ça souffle fort, la fumée part vers les maisons !'
            : 'Pas trop de vent, la fumée monte droit.',
      ),
      Q(
        'maisons',
        'Y a-t-il des habitations à proximité ?',
        (c) => yes(c, 'maisons') ? 'Oui, le lotissement des Chênes est juste à côté !' : "Non, c'est en pleine forêt.",
      ),
      Q('personnes', 'Voyez-vous des personnes en danger ?', (c) => 'Non, je crois pas.'),
    ],
    advice: [
      Advice(
        'eloigner',
        'Éloignez-vous du feu, dos au vent, et gardez votre téléphone allumé.',
        (c) => "D'accord, je redescends vers le parking.",
        1,
      ),
      Advice(
        'eteindre',
        'Essayez de taper les flammes avec des branches.',
        (c) => "J'essaie… ça brûle trop, j'ai les cheveux roussis !",
        -1,
      ),
    ],
    needs: (c) => needsOf({VType.ccf: 1, VType.fpt: yes(c, 'vent') || yes(c, 'maisons') ? 1 : 0}),
    ambiance: (c) => yes(c, 'vent')
        ? 'Feu de forêt, vent fort, propagation rapide. On attaque par le flanc.'
        : 'Feu de sous-bois, environ 1 hectare, peu de vent. On attaque.',
    report: (c, good) => good
        ? 'Feu fixé. 2 hectares brûlés, aucune habitation touchée.'
        : 'Feu fixé mais 15 hectares détruits. Il fallait être plus rapide.',
  ),

  // ---------------------------------------------- Feu d'entrepôt
  Scenario(
    id: 'feu_entrepot',
    nature: Nature.feuIndustriel,
    zone: Zone.zi,
    minLevel: 2,
    weight: 0.6,
    target: 14,
    work: 60,
    setup: (c, r) {
      person(c, r, female: false);
      c.v['blesse'] = r.nextBool();
      c.v['chimique'] = r.nextBool();
    },
    caller: (c) => '${an(c)} · gardien de nuit',
    opening: (c) => [
      "Ici le gardien de Plastiflex… il y a le feu dans l'entrepôt ! C'est énorme, ça fait des explosions !",
    ],
    questions: [
      adresse((c) => "Zone industrielle des Gravières, rue de l'Industrie, chez Plastiflex !"),
      Q('taille', 'Quelle partie du bâtiment brûle ?', (c) => 'Tout le stockage… le toit commence à s\'effondrer !'),
      Q(
        'personnes',
        "Y a-t-il des employés à l'intérieur ?",
        (c) => yes(c, 'blesse')
            ? 'Un cariste est sorti, il a les mains brûlées !'
            : "Non, l'équipe de nuit est sortie, ils sont sur le parking.",
      ),
      Q(
        'produits',
        'Y a-t-il des produits dangereux stockés ?',
        (c) => yes(c, 'chimique') ? 'Oui… des fûts de solvants au fond…' : 'Que du plastique et du carton.',
      ),
    ],
    advice: [
      Advice(
        'evacuer',
        'Rassemblez tout le personnel loin du bâtiment, comptez-les, et ouvrez le portail.',
        (c) => 'OK, tout le monde au portail, je compte… tout le monde est là.',
        1,
      ),
      Advice(
        'extincteur',
        'Essayez de l\'éteindre avec les extincteurs.',
        (c) => "On a essayé… c'est beaucoup trop gros, on a reculé.",
        -1,
      ),
    ],
    needs: (c) => needsOf({VType.fpt: 2, VType.epa: 1, VType.vsav: yes(c, 'blesse') ? 1 : 0}),
    ambiance: (c) =>
        'Feu d\'entrepôt de 2000 m², toiture effondrée${yes(c, 'chimique') ? ', solvants présents, périmètre de 200 m' : ''}. Feu de grande ampleur.',
    report: (c, good) => good
        ? "Feu d'entrepôt maîtrisé après une longue lutte. Pas de victime grave."
        : 'Entrepôt détruit, le feu a gagné le bâtiment voisin.',
  ),

  // ---------------------------------------------- Inondation
  Scenario(
    id: 'inondation',
    nature: Nature.inondation,
    zone: Zone.ville,
    weight: 0.9,
    target: 45,
    work: 30,
    setup: (c, r) {
      person(c, r);
      c.v['cm'] = 10 + r.nextInt(50);
      c.v['elec'] = r.nextBool();
    },
    caller: (c) => '${an(c)} · dépité${fe(c)}',
    opening: (c) => ["Bonsoir, avec l'orage ma cave est complètement inondée… et l'eau continue de monter !"],
    questions: [
      adresse(),
      Q('hauteur', "Quelle hauteur d'eau ?", (c) => "${c.v['cm']} centimètres à peu près."),
      Q(
        'elec',
        "Y a-t-il de l'électricité dans l'eau ?",
        (c) => yes(c, 'elec')
            ? "Le compteur est juste au-dessus… et la machine à laver est dans l'eau."
            : "Non, rien d'électrique en bas.",
      ),
      Q('personnes', "Quelqu'un est-il en danger ?", (c) => 'Non non, on est tous en haut.'),
    ],
    advice: [
      Advice(
        'couper',
        "Coupez l'électricité au disjoncteur si vous êtes au sec, et ne descendez pas.",
        (c) => "C'est coupé. On reste en haut.",
        1,
      ),
      Advice(
        'descendre',
        'Descendez récupérer vos affaires avant que ça monte.',
        (c) => yes(c, 'elec') ? "J'y vais… AÏE ! J'ai pris une décharge !" : "Bon… j'ai sauvé deux cartons.",
        -1,
        apply: (c) {
          if (yes(c, 'elec')) c.v['electrise'] = true;
        },
      ),
    ],
    needs: (c) => needsOf({VType.vtu: 1, VType.vsav: yes(c, 'electrise') ? 1 : 0}),
    ambiance: (c) => "Cave inondée, ${c.v['cm']} cm d'eau. On met en place l'aspiration.",
    report: (c, good) => good
        ? 'Cave épuisée, compteur sécurisé. Les sinistrés remercient.'
        : 'Cave épuisée, mais les sinistrés ont attendu longtemps.',
  ),

  // ---------------------------------------------- Guêpes (ou pas)
  Scenario(
    id: 'guepes',
    nature: Nature.animal,
    zone: Zone.ville,
    weight: 0.9,
    target: 40,
    work: 20,
    setup: (c, r) {
      person(c, r, female: true);
      c.v['allergie'] = r.nextDouble() < 0.4;
      if (yes(c, 'allergie')) {
        c.v['critique'] = true;
        c.v['target'] = 10.0;
      }
    },
    caller: (c) => '${an(c)} · calme',
    opening: (c) => [
      "Bonjour, il y a un énorme nid de guêpes sous mon toit, au-dessus de la terrasse… les enfants ne peuvent plus jouer dehors.",
    ],
    questions: [
      adresse(),
      Q(
        'pique',
        "Quelqu'un a-t-il été piqué ?",
        (c) => yes(c, 'allergie')
            ? "Oh… attendez… mon mari a été piqué tout à l'heure… il a le visage qui gonfle et il respire mal, là…"
            : 'Non, personne.',
      ),
      Q(
        'allergique',
        'Est-il allergique ? A-t-il un stylo d\'adrénaline ?',
        (c) => 'Il est allergique oui… le stylo est dans le tiroir, je crois !',
        after: 'pique',
        when: (c) => yes(c, 'allergie'),
      ),
      Q('ou', 'Où se trouve le nid exactement ?', (c) => 'Sous la toiture, au-dessus de la terrasse.'),
    ],
    advice: [
      Advice(
        'stylo',
        'Faites-lui l\'injection avec le stylo, dans la cuisse, même à travers le pantalon.',
        (c) => "C'est fait… il respire un peu mieux…",
        1,
        after: 'allergique',
        apply: (c) => c.v['stylo'] = true,
      ),
      Advice(
        'fermer',
        'Fermez les fenêtres et éloignez les enfants de la terrasse.',
        (c) => "D'accord, tout le monde à l'intérieur.",
        1,
      ),
      Advice(
        'bombe',
        'Aspergez le nid avec une bombe insecticide.',
        (c) => 'Elles sortent toutes ! Il y en a partout !!',
        -1,
      ),
    ],
    needs: (c) => yes(c, 'allergie') ? {VType.vsav: 1, VType.smur: 1} : {VType.vtu: 1},
    ambiance: (c) => yes(c, 'allergie')
        ? (yes(c, 'stylo')
              ? 'Choc anaphylactique, adrénaline injectée par la famille, victime stabilisée.'
              : 'Choc anaphylactique en cours, œdème du visage, détresse respiratoire !')
        : 'Nid de guêpes sous la toiture. On traite.',
    report: (c, good) => yes(c, 'allergie')
        ? (good
              ? 'Victime stabilisée, transportée au CH avec le SMUR. Bien vu d\'avoir posé la question.'
              : 'Choc anaphylactique trop avancé… arrêt cardiaque. Décès.')
        : 'Nid détruit. Les enfants peuvent retourner jouer.',
  ),

  // ---------------------------------------------- Chat dans l'arbre
  Scenario(
    id: 'chat',
    nature: Nature.animal,
    zone: Zone.ville,
    weight: 0.7,
    target: 60,
    work: 20,
    setup: (c, r) {
      person(c, r, female: true);
      c.v['jours'] = 1 + r.nextInt(3);
    },
    caller: (c) => '${an(c)} · dame âgée, émue',
    opening: (c) => [
      "Oui bonsoir… mon chat Pompon est coincé dans le cerisier depuis ${c.v['jours']} jour${(c.v['jours'] as int) > 1 ? 's' : ''}… il miaule, ça me fend le cœur…",
    ],
    questions: [
      adresse(),
      Q('hauteur', 'À quelle hauteur est-il ?', (c) => 'Oh… 5 ou 6 mètres, tout en haut !'),
      Q('essaye', "Avez-vous essayé de l'attirer avec de la nourriture ?", (c) => 'Oui, avec du thon… il bouge pas.'),
      Q('danger', 'Une personne est-elle en danger ?', (c) => 'Non… juste Pompon…'),
    ],
    advice: [
      Advice(
        'patience',
        "Laissez une gamelle au pied de l'arbre et éloignez-vous, il redescend souvent seul.",
        (c) => 'Bon… je vais essayer… mais venez quand même, hein ?',
        1,
      ),
      Advice(
        'echelle',
        "Montez à l'échelle pour le récupérer.",
        (c) => "À mon âge ?! … bon… *bruit de chute* … aïe, mon poignet !",
        -2,
        apply: (c) => c.v['mamie'] = true,
      ),
    ],
    needs: (c) => needsOf({VType.vtu: 1, VType.vsav: yes(c, 'mamie') ? 1 : 0}),
    ambiance: (c) => 'Chat perché à 6 mètres, propriétaire très émue. On sort l\'échelle à coulisse.',
    report: (c, good) => yes(c, 'mamie')
        ? 'Chat récupéré. La propriétaire est transportée au CH pour son poignet.'
        : 'Pompon récupéré sain et sauf. La dame nous a offert des madeleines.',
  ),

  // ---------------------------------------------- Ascenseur
  Scenario(
    id: 'ascenseur',
    nature: Nature.personneBloquee,
    zone: Zone.centre,
    weight: 0.8,
    target: 25,
    work: 15,
    setup: (c, r) {
      person(c, r);
      c.v['angoisse'] = r.nextBool();
    },
    caller: (c) => '${an(c)} · coincé${fe(c)}',
    opening: (c) => [
      "Allô ? Je suis coincé${fe(c)} dans l'ascenseur de mon immeuble, entre deux étages… ça fait 40 minutes !",
    ],
    questions: [
      adresse(),
      Q('combien', 'Combien êtes-vous dans la cabine ?', (c) => 'Deux, avec une dame âgée.'),
      Q(
        'etat',
        'Comment allez-vous ? Quelqu\'un se sent mal ?',
        (c) => yes(c, 'angoisse')
            ? "La dame respire très vite… elle dit qu'elle va s'évanouir…"
            : 'Ça va, on a juste chaud.',
      ),
      Q('alarme', "Avez-vous appuyé sur le bouton d'alarme ?", (c) => 'Oui, personne ne répond !'),
    ],
    advice: [
      Advice(
        'calme',
        "Restez calmes, asseyez-vous, respirez lentement. N'essayez pas d'ouvrir les portes.",
        (c) => "D'accord… on respire… ça va un peu mieux.",
        1,
      ),
      Advice(
        'forcer',
        'Essayez d\'écarter les portes à la main.',
        (c) => 'On a forcé… la cabine a bougé d\'un coup !! On a eu super peur !',
        -1,
      ),
    ],
    needs: (c) => needsOf({VType.vtu: 1, VType.vsav: yes(c, 'angoisse') ? 1 : 0}),
    ambiance: (c) => 'Cabine bloquée entre le 3e et le 4e. On manœuvre.',
    report: (c, good) =>
        "Deux personnes dégagées de la cabine.${yes(c, 'angoisse') ? " La dame a été examinée : crise d'angoisse." : ''}",
  ),

  // ---------------------------------------------- Enfant, maman inconsciente
  Scenario(
    id: 'enfant_maman',
    nature: Nature.malaise,
    zone: Zone.ville,
    weight: 0.6,
    target: 12,
    work: 25,
    critical: true,
    setup: (c, r) {
      victim(c, r, female: true, min: 30, max: 42);
      c.v['af'] = r.nextBool();
      c.v['enfant'] = pick(r, c.v['af'] == true ? prenomsF : prenomsH);
    },
    caller: (c) => "Voix d'enfant · très petite",
    opening: (c) => c.isCallback
        ? ['*sanglote* Allô… pourquoi vous avez raccroché… maman elle se réveille toujours pas…']
        : ["Allô ? … c'est les pompiers ? … Ma maman elle se réveille pas… elle est par terre dans la cuisine."],
    questions: [
      adresse((c) => "Euh… j'habite au ${c.address}… c'est la maison avec le portail bleu."),
      Q('nom', "Comment tu t'appelles ? Quel âge as-tu ?", (c) => "Je m'appelle ${c.v['enfant']}… j'ai 7 ans."),
      Q(
        'respire',
        'Est-ce que ta maman respire ? Regarde si son ventre bouge.',
        (c) => 'Oui… son ventre il bouge… mais elle répond pas quand je l\'appelle.',
      ),
      Q(
        'malade',
        'Est-ce que ta maman est malade ? Elle prend des médicaments ?',
        (c) => "Elle a un truc pour le sucre… elle se pique au doigt…",
      ),
      Q('adulte', 'Il y a un autre adulte avec toi ?', (c) => 'Non… papa il travaille la nuit.'),
    ],
    advice: [
      Advice(
        'pls',
        "Tu vas m'aider : tourne ta maman sur le côté, comme je t'explique, et reste près d'elle.",
        (c) => "D'accord… voilà… elle est sur le côté…",
        1,
      ),
      Advice(
        'porte',
        "Tu peux ouvrir la porte d'entrée pour les pompiers ? Et allumer la lumière ?",
        (c) => "Oui, j'ai ouvert !",
        1,
        apply: (c) => c.v['porte'] = true,
      ),
      Advice('boire', "Donne-lui un verre d'eau avec du sucre.", (c) => 'Elle arrive pas à boire… ça coule…', -1),
    ],
    needs: (c) => {VType.vsav: 1, VType.smur: 1},
    ambiance: (c) =>
        "Femme inconsciente, glycémie effondrée. ${yes(c, 'porte') ? "Porte ouverte par l'enfant, super réflexe." : 'On a dû forcer la porte.'}",
    report: (c, good) => good
        ? "Maman réveillée et transportée au CH. Le petit ${c.v['enfant']} a été un héros. Toi aussi."
        : 'Coma hypoglycémique prolongé… victime en réanimation, pronostic réservé.',
  ),

  // ---------------------------------------------- Canular d'enfants
  Scenario(
    id: 'canular',
    nature: Nature.feuHabitation,
    zone: Zone.ville,
    weight: 1.0,
    kind: (c) => Kind.canular,
    setup: (c, r) {},
    caller: (c) => 'Numéro masqué · voix d\'enfant',
    opening: (c) => ['*rires étouffés* Allô… euh… y a le feu… dans… dans ma culotte ! *éclats de rire*'],
    questions: [
      adresse((c) => 'Euh… *chuchote* … au 1 rue du Pipi ! *rires*'),
      Q('quoi', 'Que se passe-t-il exactement ?', (c) => 'Bah… le feu… *pouffe* … chez Dylan ! HAHAHA'),
      Q('age', 'Quel âge as-tu ?', (c) => 'Euh… 25 ans ! *rires en fond*'),
      Q('parents', 'Tes parents sont à côté de toi ?', (c) => 'Non ! … euh…'),
    ],
    advice: [
      Advice(
        'serieux',
        "Ce numéro sert à sauver des vies. Pendant que tu joues, quelqu'un en danger ne peut pas nous joindre.",
        (c) => "… pardon m'sieur… *tut tut tut*",
        1,
        apply: (c) => c.v['coupe'] = true,
      ),
    ],
    needs: (c) => {},
    ambiance: (c) => 'Rien sur place, adresse fantaisiste. Canular.',
    report: (c, good) => 'Retour caserne. Canular.',
  ),

  // ---------------------------------------------- La pizza
  Scenario(
    id: 'pizza',
    nature: Nature.blesse,
    zone: Zone.ville,
    minLevel: 1,
    weight: 0.7,
    kind: (c) => yes(c, 'vrai') ? Kind.police : Kind.canular,
    setup: (c, r) {
      c.v['vrai'] = r.nextBool();
      person(c, r, female: yes(c, 'vrai'));
    },
    caller: (c) => yes(c, 'vrai') ? '${an(c)} · voix basse' : '${an(c)} · musique en fond',
    opening: (c) => yes(c, 'vrai')
        ? ['Bonsoir… je voudrais commander une pizza… une grande, s\'il vous plaît.']
        : ['Ouais bonsoir… c\'est pour une pizza… une 4 fromages… *rires derrière*'],
    questions: [
      adresse(
        (c) => yes(c, 'vrai') ? "C'est au ${c.address}… s'il vous plaît, faites vite." : 'Au… euh… chez moi ! Hahaha',
      ),
      Q(
        'pizza',
        'Vous avez appelé les pompiers, pas une pizzeria.',
        (c) => yes(c, 'vrai')
            ? 'Oui… je sais. Une grande pizza, avec… avec du fromage.'
            : 'Ah m… les pompiers ?! Hahaha les gars, c\'est les pompiers !',
      ),
      Q(
        'danger',
        'Êtes-vous en danger ? Répondez juste par oui ou par non.',
        (c) => yes(c, 'vrai') ? '… Oui.' : 'En danger de mourir de faim ouais ! HAHAHA',
      ),
      Q(
        'menace',
        'La personne qui vous menace est-elle à côté de vous ?',
        (c) => 'Oui… dans la pièce d\'à côté… il a bu… *voix d\'homme au loin : C\'EST QUI ?!*',
        after: 'danger',
        when: (c) => yes(c, 'vrai'),
      ),
      Q('blessee', 'Êtes-vous blessée ?', (c) => 'Un peu… le bras…', after: 'danger', when: (c) => yes(c, 'vrai')),
    ],
    advice: [
      Advice(
        'rester',
        'Restez en ligne si vous pouvez. Je préviens la police tout de suite.',
        (c) => "D'accord… merci… *chuchote*",
        1,
        after: 'danger',
        when: (c) => yes(c, 'vrai'),
      ),
    ],
    needs: (c) => yes(c, 'vrai') ? {VType.police: 1} : {},
    ambiance: (c) => yes(c, 'vrai')
        ? 'Police sur place, homme interpellé. Femme légèrement blessée.'
        : 'Rien sur place. Des jeunes qui rigolent dans un appartement…',
    report: (c, good) =>
        yes(c, 'vrai') ? 'Violences conjugales. La victime est en sécurité. Bien joué d\'avoir compris.' : 'Canular.',
  ),

  // ---------------------------------------------- Voisins bruyants (17)
  Scenario(
    id: 'voisins',
    nature: Nature.blesse,
    zone: Zone.centre,
    weight: 0.6,
    kind: (c) => Kind.police,
    setup: (c, r) => person(c, r),
    caller: (c) => '${an(c)} · très énervé${fe(c)}',
    opening: (c) => [
      "Oui bonsoir, mes voisins du dessus font la fête depuis 20 heures, musique à fond, c'est IN-SUP-POR-TABLE ! Je travaille demain, moi !",
    ],
    questions: [
      adresse(),
      Q(
        'danger',
        'Y a-t-il un danger, des blessés, un incendie ?',
        (c) => 'Non, mais c\'est un danger pour mes oreilles, oui !',
      ),
      Q(
        'bagarre',
        'Entendez-vous des bagarres, des cris de détresse ?',
        (c) => 'Non, ils chantent du Céline Dion. Faux, en plus.',
      ),
    ],
    needs: (c) => {},
    ambiance: (c) => 'Fête bruyante, aucun danger. Ce n\'est pas pour nous.',
    report: (c, good) => 'Tapage nocturne.',
  ),

  // ---------------------------------------------- Mal aux dents (15)
  Scenario(
    id: 'dents',
    nature: Nature.malaise,
    zone: Zone.ville,
    weight: 0.6,
    kind: (c) => Kind.medecin,
    setup: (c, r) => person(c, r, female: false),
    caller: (c) => '${an(c)} · plaintif',
    opening: (c) => [
      "Allô, bonsoir… j'ai super mal aux dents depuis trois jours… là j'en peux plus… vous pouvez envoyer quelqu'un ?",
    ],
    questions: [
      adresse(),
      Q(
        'fievre',
        'Avez-vous de la fièvre ? Le visage gonflé ?',
        (c) => 'Un peu chaud peut-être… la joue un peu gonflée…',
      ),
      Q('respire', 'Avez-vous du mal à respirer ou à avaler ?', (c) => 'Non, ça va de ce côté-là.'),
    ],
    needs: (c) => {},
    ambiance: (c) => "Douleur dentaire. Rien d'urgent pour nous.",
    report: (c, good) => 'Rage de dents.',
  ),
];
