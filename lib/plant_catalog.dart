class PlantCareGuide {
  const PlantCareGuide({
    required this.slug,
    required this.commonName,
    required this.scientificName,
    required this.family,
    required this.origin,
    required this.abundance,
    required this.description,
    required this.sunlight,
    required this.watering,
    required this.fertilizing,
    required this.soil,
    required this.climate,
    required this.pruning,
  });

  final String slug;
  final String commonName;
  final String scientificName;
  final String family;
  final String origin;
  final String abundance;
  final String description;
  final String sunlight;
  final String watering;
  final String fertilizing;
  final String soil;
  final String climate;
  final String pruning;
}

const plantCareCatalog = <String, PlantCareGuide>{
  'banana': PlantCareGuide(
    slug: 'banana',
    commonName: 'Bananeira',
    scientificName: 'Musa acuminata',
    family: 'Musaceae',
    origin: 'Asia tropical e subtropical, especialmente o Sudeste Asiatico.',
    abundance:
        'Regioes tropicais umidas da Asia, America Latina, Caribe e Africa.',
    description:
        'Erva perene de grande porte, com pseudocaule formado pelas bases das '
        'folhas. As variedades cultivadas produzem cachos e se multiplicam '
        'principalmente por brotos laterais.',
    sunlight:
        'Sol pleno, idealmente 6 a 8 horas por dia. Proteja de ventos fortes, '
        'que rasgam as folhas e podem derrubar a planta.',
    watering:
        'Mantenha o solo uniformemente umido, regando profundamente quando a '
        'camada superficial comecar a secar. Nao deixe as raizes encharcadas.',
    fertilizing:
        'E uma planta exigente em nutrientes. Use composto organico e adubo '
        'equilibrado com bom teor de potassio durante o crescimento, sempre '
        'seguindo a dose do fabricante.',
    soil:
        'Fertil, rico em materia organica, profundo e bem drenado. Cobertura '
        'morta ajuda a conservar umidade sem encostar no pseudocaule.',
    climate:
        'Prefere calor e umidade, aproximadamente entre 20 e 30 C. Frio '
        'intenso e geada prejudicam folhas e frutos.',
    pruning:
        'Remova folhas secas ou doentes. Apos a colheita, corte o pseudocaule '
        'que produziu e mantenha um broto vigoroso para o proximo ciclo.',
  ),
  'coconut': PlantCareGuide(
    slug: 'coconut',
    commonName: 'Coqueiro',
    scientificName: 'Cocos nucifera',
    family: 'Arecaceae',
    origin: 'Malesia central ate o sudoeste do Pacifico.',
    abundance:
        'Litorais e planicies tropicais da Asia, Pacifico, Caribe, Africa e '
        'Nordeste do Brasil.',
    description:
        'Palmeira tropical de tronco unico, folhas pinadas e frutos grandes. '
        'Tolera maresia, mas precisa de calor e espaco para desenvolver copa e '
        'sistema radicular.',
    sunlight:
        'Sol pleno, com pelo menos 6 horas de luz direta. Evite locais '
        'sombreados por construcoes ou arvores maiores.',
    watering:
        'Coqueiros jovens precisam de regas regulares. Plantas estabelecidas '
        'toleram periodos secos, mas produzem melhor com umidade constante e '
        'boa drenagem.',
    fertilizing:
        'Use fertilizante proprio para palmeiras, com potassio, magnesio e '
        'micronutrientes como manganes. Distribua na area sob a copa e siga o '
        'rotulo.',
    soil:
        'Profundo e bem drenado; adapta-se a solos arenosos e tolera salinidade '
        'moderada. Nao plante em pontos que permanecem alagados.',
    climate:
        'Clima tropical quente e umido. E sensivel a geadas e a temperaturas '
        'baixas prolongadas.',
    pruning:
        'Retire apenas folhas completamente secas, quebradas ou doentes. Nao '
        'corte folhas verdes; monitore frutos altos pelo risco de queda.',
  ),
  'coffee': PlantCareGuide(
    slug: 'coffee',
    commonName: 'Cafeeiro',
    scientificName: 'Coffea arabica',
    family: 'Rubiaceae',
    origin: 'Sudoeste da Etiopia, leste do Sudao do Sul e norte do Quenia.',
    abundance:
        'Planaltos tropicais da America Latina e Africa Oriental, com ampla '
        'producao no Brasil, Colombia e Etiopia.',
    description:
        'Arbusto perene de folhas brilhantes, flores brancas aromaticas e '
        'frutos conhecidos como cerejas. As sementes torradas originam o cafe.',
    sunlight:
        'Luz intensa filtrada ou sol suave. Em regioes muito quentes, sombra '
        'parcial nas horas mais fortes reduz estresse nas folhas.',
    watering:
        'Mantenha umidade regular durante crescimento, floracao e formacao dos '
        'frutos. Regue quando a superficie secar, sem deixar agua acumulada.',
    fertilizing:
        'Aplique composto organico e adubo equilibrado em pequenas parcelas '
        'durante o periodo de crescimento. Ajuste por analise do solo e pelo '
        'porte da planta.',
    soil:
        'Levemente acido, rico em materia organica e bem drenado. Uma faixa de '
        'pH proxima de 5,5 a 6,5 costuma ser adequada.',
    climate:
        'Prefere temperaturas amenas de altitude, aproximadamente 18 a 24 C, '
        'boa umidade e protecao contra geada e calor extremo.',
    pruning:
        'Remova ramos secos, fracos ou doentes e controle a altura para '
        'facilitar ventilacao, colheita e renovacao dos ramos produtivos.',
  ),
  'mango': PlantCareGuide(
    slug: 'mango',
    commonName: 'Mangueira',
    scientificName: 'Mangifera indica',
    family: 'Anacardiaceae',
    origin:
        'Sul da Asia, do Assam e Himalaya Oriental ate Myanmar, Tailandia e '
        'sul da China.',
    abundance:
        'Regioes tropicais e subtropicais, sobretudo Sul da Asia, Sudeste '
        'Asiatico, America Latina e Africa.',
    description:
        'Arvore perene de copa ampla, folhas lanceoladas e frutos aromaticos. '
        'Pode atingir grande porte quando nao recebe poda de formacao.',
    sunlight:
        'Sol pleno para crescer e frutificar bem. Escolha uma area aberta, '
        'quente e afastada de estruturas e redes eletricas.',
    watering:
        'Regue mudas com frequencia ate o estabelecimento. Arvores adultas '
        'precisam de agua principalmente em secas prolongadas; excesso de agua '
        'prejudica raizes e frutos.',
    fertilizing:
        'Adube plantas jovens em pequenas doses ao longo do ano. Em arvores '
        'adultas, evite excesso de nitrogenio e priorize potassio conforme '
        'analise do solo.',
    soil:
        'Adapta-se a varios solos, desde que sejam profundos e bem drenados. '
        'Evite baixadas sujeitas a alagamento.',
    climate:
        'Clima tropical ou subtropical quente, com periodo mais seco '
        'favorecendo a floracao. Plantas jovens sao sensiveis a geadas.',
    pruning:
        'Faca poda de formacao quando jovem e poda leve apos a colheita. '
        'Retire ramos cruzados, secos ou doentes e preserve a copa ventilada.',
  ),
  'tomato': PlantCareGuide(
    slug: 'tomato',
    commonName: 'Tomateiro',
    scientificName: 'Solanum lycopersicum',
    family: 'Solanaceae',
    origin: 'Cultigen de origem andina, associado ao Peru.',
    abundance:
        'Cultivado mundialmente em hortas e lavouras de clima quente ou em '
        'estufas durante periodos frios.',
    description:
        'Planta herbacea de ciclo relativamente curto, caules flexiveis, '
        'flores amarelas e frutos de muitas formas e cores. A maioria das '
        'variedades precisa de tutoramento.',
    sunlight:
        'Sol pleno, com 6 a 8 horas de luz direta. Boa ventilacao ajuda a '
        'reduzir doencas foliares.',
    watering:
        'Mantenha a umidade uniforme e regue diretamente o solo. Como '
        'referencia, cerca de 25 mm por semana entre chuva e irrigacao, '
        'ajustando ao calor, ao vaso e ao tipo de solo.',
    fertilizing:
        'Use composto e adubacao orientada por analise do solo. Evite excesso '
        'de nitrogenio; na floracao, prefira formulacoes proprias para tomate '
        'e siga o rotulo.',
    soil:
        'Fertil, solto e bem drenado, com materia organica. pH em torno de 6,0 '
        'a 6,8 favorece a disponibilidade de nutrientes.',
    climate:
        'Desenvolve-se melhor em temperaturas moderadamente quentes. Geada, '
        'calor extremo e grandes oscilacoes de umidade reduzem a frutificacao.',
    pruning:
        'Use estaca ou gaiola, retire folhas inferiores doentes e mantenha '
        'frutos longe do solo. A retirada de brotos depende do tipo de tomate.',
  ),
};

PlantCareGuide? plantCareGuideFor({String? slug, String? commonName}) {
  final normalizedSlug = slug?.trim().toLowerCase();
  if (normalizedSlug != null && normalizedSlug.isNotEmpty) {
    final guide = plantCareCatalog[normalizedSlug];
    if (guide != null) {
      return guide;
    }
  }

  final normalizedName = commonName?.trim().toLowerCase();
  if (normalizedName == null || normalizedName.isEmpty) {
    return null;
  }
  const aliases = <String, String>{
    'bananeira': 'banana',
    'coqueiro': 'coconut',
    'cafe': 'coffee',
    'cafeeiro': 'coffee',
    'mangueira': 'mango',
    'tomateiro': 'tomato',
  };
  final aliasSlug = aliases[normalizedName];
  if (aliasSlug != null) {
    return plantCareCatalog[aliasSlug];
  }
  for (final guide in plantCareCatalog.values) {
    if (guide.commonName.toLowerCase() == normalizedName) {
      return guide;
    }
  }
  return null;
}
