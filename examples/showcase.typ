// Ce que scrawl sait faire — chaque figure avec le code qui la produit.
//
// Le code affiché est CELUI QUI S'EXÉCUTE : `demo` reçoit un bloc brut,
// l'imprime tel quel, puis l'évalue. Recopier l'exemple à côté de son image
// marche un mois, puis quelqu'un corrige l'un sans l'autre.

#import "@preview/scrawl:0.1.0": *
#set page(width: 21cm, height: auto, margin: 1.1cm, fill: white)
#set text(font: ("Libertinus Serif", "DejaVu Serif"), size: 9.5pt)
#show raw: set text(font: ("DejaVu Sans Mono", "Liberation Mono"), size: 6.9pt)
#set par(justify: false, leading: 0.6em)

#let scope = (
  scrawl: scrawl, scrawl-box: scrawl-box, scrawl-ellipse: scrawl-ellipse,
  scrawl-underline: scrawl-underline, hl: hl,
  rect-pts: rect-pts, rounded-rect-pts: rounded-rect-pts,
  circle-pts: circle-pts, arc-pts: arc-pts,
  rough: rough, resample: resample, randoms: randoms,
  lines: lines, region: region, path-shape: path-shape,
)

// Une entrée : le code à gauche, son rendu à droite.
#let demo(src, ratio: 55%) = {
  let body = (if type(src) == str { src } else { src.text }).trim("\n")
  block(breakable: false, width: 100%, inset: (y: 4pt), grid(
    columns: (ratio, 1fr), column-gutter: 9pt,
    align: (top + left, top + center),
    block(width: 100%, fill: rgb("#f6f8fa"), radius: 3pt,
      inset: (x: 6pt, y: 5pt), stroke: 0.4pt + rgb("#d0d7de"),
      raw(body, lang: "typ", block: true)),
    block(width: 100%, eval(body, mode: "markup", scope: scope)),
  ))
}

#align(center)[
  #text(size: 20pt, weight: "bold")[scrawl]
  #v(-7pt)
  #text(size: 14pt, fill: rgb("#444"))[#emoji.hand.write FERGOUS Abdelhak]
  #v(4pt)
  #text(size: 10pt, fill: rgb("#555"))[
    des formes à main levée, en Typst pur — aucun greffon, aucune dépendance
  ]
]

#v(3mm)

= Les trois raccourcis

Ils mesurent leur contenu : le cadre épouse ce qu'on y met.

#demo(```
#grid(columns: 3, column-gutter: 5mm, align: horizon,
  scrawl-box(fill: rgb("#fffbe6"))[un cadre],
  scrawl-ellipse(paint: rgb("#166534"))[cerclé],
  [du texte #scrawl-underline[souligné] ici],
)
```)

#demo(```
Et un #hl[surligneur], en #hl(colour: rgb("#B7E3FF"))[deux teintes].
```)

= Le canevas

Coordonnées en centimètres, *y vers le haut*. Le corps reçoit six fonctions
déjà liées au canevas : `shape`, `lines`, `region`, `rough`, `label`, `arrow`.

#demo(```
#scrawl(width: 8.4cm, height: 3.6cm, (shape, ..) => {
  shape(rounded-rect-pts((0.2, 0.2), (2.6, 3.4), radius: 0.3),
    paint: rgb("#2B6CB0"), fill: rgb("#EAF2FB"), weight: 1.2pt)
  shape(circle-pts((4.4, 1.8), 1.3),
    paint: rgb("#C2410C"), fill: rgb("#FFF1E7"))
  shape(((6.2, 0.3), (8.2, 0.3), (7.2, 3.3)),
    paint: rgb("#166534"), fill: rgb("#EAF7EE"), weight: 1.2pt)
})
```)

= Un graphique, façon tableau noir

`arrow` trace le trait et sa pointe ; `label` pose du texte aux coordonnées du
canevas, sans conversion à faire soi-même.

#demo(ratio: 55%, ```
#scrawl(width: 8.2cm, height: 4.6cm, roughness: 1.1,
        (shape, lines, region, rough, label, arrow) => {
  arrow((0.8, 0.7), (7.9, 0.7), weight: 1.2pt)
  arrow((0.8, 0.7), (0.8, 4.2), weight: 1.2pt)
  shape(((1.0, 0.9), (2.4, 1.2), (3.4, 1.7), (4.4, 2.7),
         (5.6, 3.3), (6.6, 3.5), (7.4, 3.6)),
    paint: rgb("#2B6CB0"), weight: 1.6pt, closed: false)
  label((4.4, 0.2), [temps passé à peaufiner])
  label((0.6, 4.2), [qualité], anchor: right + horizon)
  label((6.4, 4.1), text(8pt)[palier])
  arrow((6.6, 3.9), (7.1, 3.7), weight: 0.7pt)
})
```)

= Des barres

Rien de spécial : un rectangle par barre, et une étiquette dessous.

#demo(ratio: 55%, ```
#scrawl(width: 8.2cm, height: 4.4cm, (shape, l, r, ro, label, arrow) => {
  let data = (("lun", 2.2), ("mar", 3.1), ("mer", 1.4),
              ("jeu", 3.6), ("ven", 2.8))
  let cols = (rgb("#2B6CB0"), rgb("#C2410C"), rgb("#166534"),
              rgb("#7C3ABA"), rgb("#B45309"))
  for (i, d) in data.enumerate() {
    let x = 1.0 + i * 1.45
    shape(rect-pts((x, 0.8), (x + 1.0, 0.8 + d.at(1))),
      paint: cols.at(i), fill: cols.at(i).lighten(72%),
      weight: 1.1pt, seed: 7 + i * 5)
    label((x + 0.5, 0.4), text(8pt, d.at(0)))
  }
  arrow((0.7, 0.8), (8.0, 0.8), weight: 1.1pt)
})
```)

= Un schéma relié

Des boîtes, des flèches entre elles : le diagramme de tableau blanc.

#demo(ratio: 55%, ```
#scrawl(width: 8.2cm, height: 3.4cm, (shape, l, r, ro, label, arrow) => {
  let boite(x, y, w, h, txt, col) = {
    shape(rounded-rect-pts((x, y), (x + w, y + h), radius: 0.2),
      paint: col, fill: col.lighten(84%), weight: 1.1pt)
    label((x + w / 2, y + h / 2), text(8.5pt, txt))
  }
  boite(0.3, 1.9, 2.3, 1.0, [écrire], rgb("#2B6CB0"))
  boite(3.2, 1.9, 2.3, 1.0, [relire], rgb("#C2410C"))
  boite(6.1, 1.9, 1.9, 1.0, [publier], rgb("#166534"))
  arrow((2.7, 2.4), (3.1, 2.4), weight: 1pt)
  arrow((5.6, 2.4), (6.0, 2.4), weight: 1pt)
  arrow((4.3, 1.8), (1.5, 1.8), weight: 0.9pt)
  label((2.9, 1.35), text(7.5pt, fill: rgb("#666"))[ça ne va pas])
})
```)

= Le degré de tremblé

`roughness` va de zéro — une règle — à un gribouillage. `hand: false`
supprime le tremblé sans changer la géométrie.

#demo(ratio: 55%, ```
#stack(dir: ttb, spacing: 1mm,
  ..(0, 0.5, 1.2, 2.5).map(r => scrawl(
    width: 8cm, height: 0.85cm, roughness: r, hand: r > 0,
    (shape, ..) => shape(rect-pts((0.1, 0.12), (7.9, 0.72)),
      paint: black),
  )))
```)

= L'amortissement

Une longue règle tremble proportionnellement moins qu'un petit cadre : juste
pour un formulaire, faux pour un croquis. `damping: false` l'annule.

#demo(ratio: 55%, ```
#grid(columns: 2, column-gutter: 3mm,
  scrawl(width: 4cm, height: 1.1cm, roughness: 2.0, (shape, ..) => {
    shape(rect-pts((0.1, 0.15), (3.9, 0.95)), paint: black)
  }),
  scrawl(width: 4cm, height: 1.1cm, roughness: 2.0, (shape, ..) => {
    shape(rect-pts((0.1, 0.15), (3.9, 0.95)), paint: black,
      damping: false)
  }),
)
```)

= Les contours sont des tableaux de points

Tout ce qui prend un contour prend un simple tableau de `(x, y)` : les
constructeurs ne sont qu'une commodité.

#demo(ratio: 55%, ```
#scrawl(width: 8.2cm, height: 3.6cm, (shape, ..) => {
  // une étoile, calculée
  let star = range(10).map(i => {
    let a = 90deg - i * 36deg
    let r = if calc.rem(i, 2) == 0 { 1.5 } else { 0.62 }
    (2.0 + r * calc.cos(a), 1.8 + r * calc.sin(a))
  })
  shape(star, paint: rgb("#B45309"), fill: rgb("#FEF3C7"),
    weight: 1.2pt)
  // un demi-disque, par un arc
  shape(arc-pts((5.6, 1.2), 1.4, 0, 180) + ((4.2, 1.2),),
    paint: rgb("#7C3ABA"), fill: rgb("#F3E8FF"), weight: 1.2pt)
})
```)

= Le déterminisme

Même `seed`, même tremblé, à chaque compilation : un document se reconstruit
à l'identique. Les deux premiers cadres partagent leur graine.

#demo(ratio: 55%, ```
#grid(columns: 4, column-gutter: 2.5mm,
  ..(1, 1, 2, 3).map(s => scrawl(
    width: 1.9cm, height: 1.2cm, seed: s, roughness: 1.4,
    (shape, ..) => shape(
      rounded-rect-pts((0.1, 0.1), (1.8, 1.1), radius: 0.15),
      paint: black),
  )))
```)

#v(2mm)
#align(center, text(size: 8pt, fill: rgb("#666"))[
  Chaque figure de cette page est produite par le code affiché à sa gauche :
  `demo` évalue la même source qu'il imprime.
])
