// =============================================================================
//  scrawl — hand-drawn shapes in plain Typst. No plugin, no dependency.
//
//  Everything here is Typst's own `curve`. Nothing is downloaded, no WASM
//  binary is loaded, and the output is a normal Typst element that measures,
//  nests and flows like any other — you can put a scrawled box inside a
//  table cell and it behaves.
//
//      #import "@preview/scrawl:0.1.0": *
//
//      #scrawl(width: 6cm, height: 3cm, {
//        shape(rect-pts((0, 0), (6, 3)), paint: black, fill: rgb("#fffbe6"))
//      })
//
//  Coordinates are in CENTIMETRES with y running UP, which is how one thinks
//  about a drawing. Typst's own origin is top-left with y running down, so
//  every function takes a `flip` — the height of the canvas — and does the
//  conversion. `scrawl()` fills it in for you; the primitives take it
//  explicitly so they can be used inside a canvas you lay out yourself.
// =============================================================================

/// A deterministic pseudo-random stream in [0, 1).
///
/// A 32-bit xorshift written out longhand. Deterministic from `seed`, so a
/// document compiles to the same bytes every time — a form that shuffled its
/// own wobble between builds would be unusable for a school that files them.
#let randoms(seed, n) = {
  let x = calc.rem(seed * 2654435761 + 1013904223, 4294967296)
  if x <= 0 { x = 12345 }
  let out = ()
  for _ in range(n) {
    x = calc.rem(x * 1103515245 + 12345, 2147483648)
    out.push(x / 2147483648.0)
  }
  out
}

#let arc-pts(centre, r, a0, a1, n: 40) = range(n + 1).map(i => {
  let a = (a0 + (a1 - a0) * i / n) * 1deg
  (centre.at(0) + r * calc.cos(a), centre.at(1) + r * calc.sin(a))
})

#let circle-pts(centre, r, n: 64) = arc-pts(centre, r, 0, 360, n: n)

#let rect-pts(a, b) = (
  (a.at(0), a.at(1)), (b.at(0), a.at(1)),
  (b.at(0), b.at(1)), (a.at(0), b.at(1)),
)

/// A rectangle with rounded corners, as a point list.
#let rounded-rect-pts(a, b, radius: 0.3, n: 8) = {
  let (x0, y0) = (calc.min(a.at(0), b.at(0)), calc.min(a.at(1), b.at(1)))
  let (x1, y1) = (calc.max(a.at(0), b.at(0)), calc.max(a.at(1), b.at(1)))
  let r = calc.min(radius, (x1 - x0) / 2, (y1 - y0) / 2)
  if r <= 0 { return rect-pts((x0, y0), (x1, y1)) }
  // ONE logical line per sum: a continuation may not BEGIN with `+`, or
  // Typst closes the expression at the line break and reads a unary plus on
  // an array. It is reported at the `+`, not at the break that caused it.
  let c1 = arc-pts((x1 - r, y0 + r), r, 270, 360, n: n)
  let c2 = arc-pts((x1 - r, y1 - r), r, 0, 90, n: n)
  let c3 = arc-pts((x0 + r, y1 - r), r, 90, 180, n: n)
  let c4 = arc-pts((x0 + r, y0 + r), r, 180, 270, n: n)
  c1 + c2 + c3 + c4
}

/// One or more polylines, as a single `curve`.
///
/// Pouring every polyline that shares a stroke into ONE `curve` as separate
/// subpaths, rather than emitting a shape each: fewer elements, and they
/// cannot drift apart under scaling.
#let lines(paths, flip: 0cm, closed: false, ..style) = {
  let segs = ()
  for path in paths {
    if path.len() < 2 { continue }
    let p0 = path.first()
    segs.push(curve.move((p0.at(0) * 1cm, flip - p0.at(1) * 1cm)))
    for p in path.slice(1) {
      segs.push(curve.line((p.at(0) * 1cm, flip - p.at(1) * 1cm)))
    }
    if closed { segs.push(curve.close(mode: "straight")) }
  }
  if segs.len() == 0 { return none }
  curve(..style, ..segs)
}

/// Fill a set of contours as one region — even-odd, so holes punch through.
#let region(contours, flip: 0cm, ..style) = lines(
  contours, flip: flip, closed: true, fill-rule: "even-odd",
  stroke: none, ..style)

/// Resample a contour so it has vertices to wobble at.
///
/// A four-point rectangle CANNOT look hand-drawn: a rough stroke only
/// deviates where there is a vertex, so a long straight edge stays
/// ruler-straight however high the roughness. Splitting every edge into
/// ~0.42 cm steps first is what makes the effect work at all.
#let resample(pts, step: 0.42, closed: true) = {
  let n = pts.len()
  if n < 2 { return pts }
  let out = ()
  let last = if closed { n } else { n - 1 }
  for i in range(last) {
    let p = pts.at(i)
    let q = pts.at(calc.rem(i + 1, n))
    let d = calc.sqrt(calc.pow(q.at(0) - p.at(0), 2)
      + calc.pow(q.at(1) - p.at(1), 2))
    let k = calc.max(1, int(d / step))
    for j in range(k) {
      let t = j / k
      out.push((p.at(0) + (q.at(0) - p.at(0)) * t,
                p.at(1) + (q.at(1) - p.at(1)) * t))
    }
  }
  if not closed { out.push(pts.last()) }
  out
}

/// A hand-drawn version of a contour: two passes, each displaced.
///
/// Drawing it ONCE reads as a wobbly line; the doubling is what the eye
/// reads as pencil. Two details that had to be right:
///
///   * a hairline must wobble LESS than an edge, or the deviation is several
///     times the line's own width and a 0.4 pt rule turns into a scribble;
///     `weight-scale` handles that from the caller's stroke width;
///   * below 0.9 pt only ONE pass is drawn, because doubling a thin rule
///     merely doubles the ink and it reads as bold.
#let rough(contour, flip: 0cm, seed: 1, roughness: 1.0, closed: true,
           weight: 1pt, damping: true, step: 0.42, ..style) = {
  let pts = resample(contour, step: step, closed: closed)
  let n = pts.len()
  if n < 2 { return none }
  let w = weight / 1pt
  // 0.06 cm is right for a card outline and far too much for a table rule
  // a page tall: the deviation compounds over the length and the line reads
  // as a scribble. Scaled by length so a long rule wobbles proportionally
  // less — measured against the scans' hand-ruled sheets.
  // The span is the DIAGONAL OF THE BOUNDING BOX, not the distance from the
  // first point to the last. On a closed contour those two coincide, so the
  // span came out as ~0 and a whole card was left undamped: at
  // `roughness: 2` its outline shook several times harder than the table
  // beside it, which is the one thing a "same style throughout" mode must
  // not do.
  let xs = pts.map(q => q.at(0))
  let ys = pts.map(q => q.at(1))
  let dx = calc.max(..xs) - calc.min(..xs)
  let dy = calc.max(..ys) - calc.min(..ys)
  let span = calc.max(0.001, calc.sqrt(dx * dx + dy * dy))
  // Damped by the SQUARE ROOT of the length, with a floor. A plain 1/span
  // (my first go) left a 18 cm table rule wobbling by 0.06 mm — invisible,
  // so the sheet looked ruled rather than drawn. Measured: 0.18 mm on a
  // long rule reads as hand-drawn without turning into a scribble.
  //
  // `damping: false` turns this off. The damping is right for a form — a
  // page-tall table rule must not shake like a doodle — but someone drawing
  // a big loose sketch wants the wobble to stay proportional. It was baked
  // in when this only had to serve lesson sheets; as a package it has to be
  // a choice.
  let damp = if damping {
    calc.max(0.42, calc.min(1.0, calc.sqrt(3.0 / calc.max(1.0, span))))
  } else { 1.0 }
  let amp = 0.06 * roughness * calc.min(1.0, 0.28 + 0.45 * w) * damp
  let passes = if w < 0.9 { 1 } else { 2 }
  let out = ()
  for pass in range(passes) {
    let r = randoms(seed + pass * 977, n * 2 + 2)
    out.push(range(n).map(i => {
      let p = pts.at(i)
      (p.at(0) + (r.at(i * 2) - 0.5) * amp,
       p.at(1) + (r.at(i * 2 + 1) - 0.5) * amp)
    }))
  }
  lines(out, flip: flip, closed: closed, fill: none, ..style)
}

/// Draw a contour: fill it, outline it, hand-drawn or ruled.
///
/// The one entry point the sheets use, so "rough or not" is decided in a
/// single place rather than at every call site.
#let path-shape(pts, flip, fill: none, paint: none, weight: 1pt,
                hand: none, seed: 1, closed: true, roughness: 1.0,
                damping: true) = {
  // Each `curve` is a BLOCK-LEVEL element, so returning two of them in a row
  // stacks them vertically: the fill landed in place and the outline was
  // pushed a whole shape-height down, out of the frame. `place` takes them
  // out of the flow so they land on top of each other, which is what
  // "outline this filled shape" has to mean. The curves already carry
  // absolute coordinates, so no offset is needed.
  let out = ()
  if fill != none {
    out.push(place(top + left, region((pts,), flip: flip, fill: fill)))
  }
  if paint != none and weight != 0pt {
    let st = (paint: paint, thickness: weight, join: "round")
    out.push(place(top + left, if hand == none {
      lines(((if closed { pts + (pts.first(),) } else { pts }),),
        flip: flip, stroke: st)
    } else {
      rough(pts, flip: flip, seed: seed, roughness: roughness,
        closed: closed, weight: weight, damping: damping, stroke: st)
    }))
  }
  if out.len() == 0 { none } else { out.join() }
}


#let hl(body, colour: rgb("#FCE94F"), seed: 3, expand: 0.14em,
        lift: 0em, hand: true, thickness: auto) = context {
  let m = measure(body)
  // A zero-width body would make `resample` divide by a zero span.
  if m.width <= 0pt { return body }
  let ex = measure(box(width: expand)).width
  let lf = measure(box(height: lift)).height
  let mid = m.height * 0.54
  // L'ÉPAISSEUR DU FEUTRE, réglable.
  //
  // 0,92 de la hauteur de boîte couvre les glyphes sans mordre sur la ligne
  // suivante — c'est la valeur de `sketchbook`, et le défaut. Mais un
  // surligneur qui ne barre qu'un mot-clé se veut parfois plus fin, et un
  // titre demande plus large. `thickness` accepte donc soit un FACTEUR (0.5
  // = moitié moins épais), soit une LONGUEUR absolue (4pt), parce que les
  // deux façons de le dire sont naturelles selon qu'on pense « proportion »
  // ou « millimètres ».
  let thick = if thickness == auto { m.height * 0.92 }
              else if type(thickness) == length { thickness }
              else { m.height * 0.92 * thickness }

  box(baseline: 0pt, {
    place(top + left, dx: -ex, dy: mid + lf, {
      let w = (m.width + 2 * ex) / 1cm
      let inset = (ex / 1cm) * 0.35
      let st = (paint: colour, thickness: thick, cap: "round")
      if hand {
        rough(((inset, 0.0), (w - inset, 0.0)), closed: false,
          seed: seed, roughness: 0.5, weight: thick, stroke: st)
      } else {
        lines((((inset, 0.0), (w - inset, 0.0)),), closed: false, stroke: st)
      }
    })
    body
  })
}

/// The frame styles `tcbox` offers, drawn with this package's own curves.
///
/// `sketchbook/tcbox.typ` is the reference for what these look like, but it
/// is built on CeTZ and on that package's theme state — neither of which
/// exists here. What carries over is the SHAPE VOCABULARY, redrawn on
/// `path-shape`: the same names produce the same picture.
///
/// `kind` is one of:
///   plain     a rectangle
///   round     rounded corners
///   tab       a title bar attached above the body
///   shadow    a rectangle with an offset drop shadow
///   double    two nested outlines
///   note      one corner folded over
/// True quand le texte environnant court de droite à gauche.
///
/// `text.dir` vaut `auto` tant que personne ne l'a fixé, auquel cas la
/// direction suit `text.lang` — il faut donc consulter les deux. Repris de
/// `sketchbook/src/tcbox.typ`, qui pose exactement le même problème.

// ---------------------------------------------------------------------------
//  The canvas
// ---------------------------------------------------------------------------

/// A drawing area, in centimetres, y running UP.
///
/// THIS IS THE REASON THE PACKAGE IS USABLE FROM OUTSIDE. The primitives all
/// take a `flip` — the canvas height — because Typst's origin is top-left
/// while one draws thinking bottom-left. Making every caller pass it is fine
/// inside one package where the call sites are known; it is a trap for
/// anyone else, who will pass `0cm` once, see the drawing vanish upwards,
/// and have no idea why.
///
/// `scrawl` closes over it: the body is a function receiving the ready-made
/// helpers, so nothing has to be threaded by hand.
///
///     #scrawl(width: 6cm, height: 3cm, (shape, ..) => {
///       shape(rect-pts((0, 0), (6, 3)), paint: black)
///     })
///
/// The block reserves its box, so a canvas sits in the text flow like an
/// image: it can go in a table cell, a grid, a figure.
#let scrawl(body, width: 6cm, height: 4cm, hand: true, seed: 1,
            roughness: 1.0) = {
  let flip = height
  // The helpers, with `flip`, `hand`, `seed` and `roughness` already bound.
  let _shape(pts, ..a) = {
    let n = a.named()
    path-shape(
      pts, flip,
      fill: n.at("fill", default: none),
      paint: n.at("paint", default: none),
      weight: n.at("weight", default: 1pt),
      hand: if n.at("hand", default: hand) { "rough" } else { none },
      seed: n.at("seed", default: seed),
      closed: n.at("closed", default: true),
      roughness: n.at("roughness", default: roughness),
      damping: n.at("damping", default: true),
    )
  }
  let _lines(paths, ..a) = lines(paths, flip: flip, ..a)
  // PLACER DU TEXTE DEMANDAIT DE CONVERTIR À LA MAIN.
  //
  // Le canevas pense en centimètres, y vers le haut ; Typst place en
  // longueurs, y vers le bas. Écrire `place(dx: 5cm, dy: height - 2cm)` à
  // chaque étiquette marche, mais c'est la conversion que `scrawl` existe
  // précisément pour éviter — et une étiquette posée au mauvais signe part
  // hors du cadre sans rien dire.
  let _label(pos, body, ..a) = {
    let n = a.named()
    let anchor = n.at("anchor", default: center + horizon)
    let dx = n.at("dx", default: 0cm)
    let dy = n.at("dy", default: 0cm)
    // LA BOÎTE DE 0 pt REPLIE LE TEXTE.
    //
    // Elle sert à ancrer : `place` vise alors le point demandé et non le
    // coin de la page. Mais une largeur nulle est aussi une largeur de
    // COLONNE, et « temps passé à peaufiner » sortait sur quatre lignes,
    // un mot chacune. Il faut donc mesurer l'étiquette et donner à la
    // boîte sa largeur réelle — l'ancrage reste, le repli disparaît.
    context {
      let m = measure(body)
      place(top + left,
        dx: pos.at(0) * 1cm + dx,
        dy: flip - pos.at(1) * 1cm + dy,
        box(width: 0pt, height: 0pt,
          place(anchor, box(width: m.width, body))))
    }
  }
  // Une flèche : le trait, puis une pointe pleine orientée par le segment.
  let _arrow(from, to, ..a) = {
    let n = a.named()
    let head = n.at("head", default: 0.32)
    let paint = n.at("paint", default: black)
    let (dx, dy) = (to.at(0) - from.at(0), to.at(1) - from.at(1))
    let d = calc.max(1e-6, calc.sqrt(dx * dx + dy * dy))
    let (ux, uy) = (dx / d, dy / d)
    // Le trait s'arrête au CREUX de la pointe, pas à son extrémité : mené
    // jusqu'au bout, il dépasse de part et d'autre du triangle.
    let base = (to.at(0) - ux * head * 0.9, to.at(1) - uy * head * 0.9)
    _shape((from, base), paint: paint,
      weight: n.at("weight", default: 1pt), closed: false,
      seed: n.at("seed", default: seed))
    let (px, py) = (-uy * head * 0.42, ux * head * 0.42)
    _shape((
      (base.at(0) + px, base.at(1) + py),
      to,
      (base.at(0) - px, base.at(1) - py),
    ), paint: paint, fill: paint, weight: n.at("weight", default: 1pt),
      seed: n.at("seed", default: seed) + 3)
  }
  let _region(cs, ..a) = region(cs, flip: flip, ..a)
  let _rough(c, ..a) = {
    let n = a.named()
    rough(c, flip: flip,
      seed: n.at("seed", default: seed),
      roughness: n.at("roughness", default: roughness),
      closed: n.at("closed", default: true),
      weight: n.at("weight", default: 1pt),
      stroke: n.at("stroke", default: black))
  }
  block(width: width, height: height, {
    // SIX HELPERS, ET L'ORDRE NE PEUT PLUS CHANGER : un appelant écrit
    // `(shape, lines, region, rough, label, arrow) => ...` et les reçoit
    // par position. Les nouveaux vont donc à la FIN, jamais au milieu.
    if type(body) == function {
      body(_shape, _lines, _region, _rough, _label, _arrow)
    }
    else { body }
  })
}

// ---------------------------------------------------------------------------
//  Ready-made shapes
// ---------------------------------------------------------------------------

/// A hand-drawn box around content — the common case, in one call.
///
/// Unlike a bare canvas this MEASURES its body first, so the frame fits what
/// is inside instead of a size guessed in advance.
#let scrawl-box(body, fill: none, paint: black, weight: 1pt, radius: 0.3,
                inset: 0.5em, hand: true, seed: 1, roughness: 1.0,
                width: auto) = context {
  let inner = block(width: width, inset: inset, body)
  let m = measure(inner)
  let w = m.width / 1cm
  let h = m.height / 1cm
  block(width: m.width, height: m.height, {
    place(top + left, path-shape(
      rounded-rect-pts((0, 0), (w, h), radius: radius), m.height,
      fill: fill, paint: paint, weight: weight,
      hand: if hand { "rough" } else { none },
      seed: seed, roughness: roughness))
    place(top + left, inner)
  })
}

/// A hand-drawn circle or ellipse around content.
#let scrawl-ellipse(body, fill: none, paint: black, weight: 1pt,
                    inset: 0.7em, hand: true, seed: 1, roughness: 1.0) = context {
  let inner = block(inset: inset, body)
  let m = measure(inner)
  // An ellipse through the corners of the text box, not around it: the
  // diagonal is what has to fit, hence the √2.
  let w = m.width / 1cm * 1.42
  let h = m.height / 1cm * 1.42
  let full = (w * 1cm, h * 1cm)
  block(width: full.at(0), height: full.at(1), {
    place(top + left, path-shape(
      arc-pts((w / 2, h / 2), 1, 0, 360, n: 48)
        .map(p => ((p.at(0) - w / 2) * w / 2 + w / 2,
                   (p.at(1) - h / 2) * h / 2 + h / 2)),
      full.at(1),
      fill: fill, paint: paint, weight: weight,
      hand: if hand { "rough" } else { none },
      seed: seed, roughness: roughness))
    place(center + horizon, inner)
  })
}

/// A hand-drawn underline under inline text.
#let scrawl-underline(body, colour: black, weight: 1pt, seed: 7,
                      roughness: 1.0, offset: 0.12em) = context {
  let m = measure(body)
  let w = m.width / 1cm
  box({
    body
    place(top + left, dy: m.height + offset,
      rough(((0, 0), (w, 0)), flip: 0cm, seed: seed, roughness: roughness,
        closed: false, weight: weight, stroke: (paint: colour,
        thickness: weight, cap: "round")))
  })
}
