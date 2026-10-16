# Passe de vérification (octobre 2026). Clé = identifiant stable de la question.
# q : nouvel énoncé · v : nouvelle valeur · fact : nouvelle anecdote · drop : retirée (désactivée sur le serveur, id conservé)
CORR = {
 'SP018': dict(q="En quelle année a eu lieu la première finale de la Coupe d'Europe des clubs champions ?", v=1956, fact="Remportée par le Real Madrid contre le Stade de Reims, à Paris."),
 'SP039': dict(q="En quelle année a eu lieu la première finale de la Coupe de France de football ?", v=1918, fact="Remportée par l'Olympique de Pantin, en mai 1918."),
 'SP052': dict(q="En quelle année le premier Paris-Dakar est-il arrivé à Dakar ?", v=1979, fact="Parti fin décembre 1978, arrivé en janvier 1979."),
 'SP114': dict(v=1910),
 'GE003': dict(v=529, fact="Elle naît en Espagne, dans le Val d'Aran, et rejoint la Dordogne pour former la Gironde."),
 'GE063': dict(v=2.08, fact="Le deuxième plus petit État du monde, agrandi par le quartier gagné sur la mer de Mareterra (2024)."),
 'GE076': dict(v=212, fact="Le pays le plus peuplé d'Amérique latine."),
 'GE085': dict(v=41.5, fact="Environ 41,5 millions, en forte hausse grâce à l'immigration."),
 'GE087': dict(v=9.0, fact="Le cap des 9 millions a été franchi en 2023."),
 'GE092': dict(drop=True),   # 5, 6 ou 7 selon les écoles : ambigu
 'NA010': dict(q="Quelle longueur peuvent atteindre les plus grands requins blancs ?", fact="La plupart mesurent 4 à 5 mètres."),
 'NA011': dict(q="Quelle longueur peuvent atteindre les plus grands crocodiles marins, plus grands reptiles actuels ?"),
 'NA013': dict(q="Quelle est l'envergure maximale d'un albatros hurleur ?"),
 'NA051': dict(q="Quelle est la hauteur d'Hyperion, le plus haut séquoia à feuilles d'if connu ?", v=116, fact="C'est le plus grand arbre vivant mesuré, en Californie."),
 'TR060': dict(q="Quelle vitesse le train à sustentation magnétique de Shanghai a-t-il atteinte en service commercial ?", fact="Il relie l'aéroport au centre en moins de 8 minutes."),
 'TR061': dict(v=2180, fact="Environ Mach 2."),
 'TR079': dict(q="Quelle est la hauteur maximale du viaduc de Millau, pylône compris ?", fact="Plus haut que la tour Eiffel."),
 'TR087': dict(v=319, fact="Après les prolongements récents des lignes 4, 11, 12 et 14."),
 'TR089': dict(v=249, fact="Environ 249 km, sur 16 lignes."),
 'TR096': dict(q="Quelle est la limitation par défaut sur les routes à double sens sans séparateur en France ?", fact="Ramenée de 90 à 80 km/h en 2018 ; certains départements sont revenus à 90."),
 'TR103': dict(v=32),
 'TE004': dict(v=34900, fact="Environ 34 900, la plupart de moins de 2 000 habitants."),
 'TE040': dict(v=508, fact="Environ 508 mètres."),
 'TE049': dict(v=2103, fact="Environ 2,1 millions (recensement 2022)."),
 'TE052': dict(v=504),
 'TE078': dict(v=11.5, fact="La plus grande ville du Brésil (recensement 2022)."),
 'HI139': dict(drop=True),   # 89 numéros mais articles bis/abrogés : ambigu
 'AR133': dict(drop=True),   # de 382 (Guinness) à plus de 600 selon les sources
}
