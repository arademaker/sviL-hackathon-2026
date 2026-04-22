
# Porting s2n-bignum to Lean 4

Slide presentation about porting the formal verification of Amazon's
[s2n-bignum](https://github.com/awslabs/s2n-bignum) library from HOL Light to
Lean 4. Built with [Verso](https://verso.lean-lang.org/).

The Lean port lives at `../bignum`
([github.com/atlas-computing-org/bignum](https://github.com/atlas-computing-org/bignum)).

The slides were presented in [Software Verification in Lean Hackathon](https://beneficial-ai-foundation.github.io/SVIL2026/).

## Prerequisites

Install [elan](https://github.com/leanprover/elan):

```
curl https://elan.lean-lang.org/install.sh -sSf | sh
```

elan will automatically download the correct Lean toolchain when you build.

## Building

```
lake update
lake build
```

## Generating Slides

```
lake build && lake exe svil2026 --output _slides
```

The slides are written to `_slides/index.html`.

## Local Development

For a live edit-and-preview workflow, run these two commands in separate terminals:

**Terminal 1** — rebuild slides automatically on every file save:

```
git ls-files | entr -c sh -c 'lake build && lake exe svil2026 --output _slides'
```

Requires [`entr`](https://eradman.com/entrproject/) (`brew install entr` on macOS).

**Terminal 2** — serve the slides locally:

```
python3 -m http.server 8765 --directory _slides
```

Then open http://localhost:8765. Refresh the browser after each save to see the updated slides.

## License

Apache 2.0

## References

### about Verso to build the slides

- https://github.com/leanprover/verso-slides VersoSlides is a Verso
  genre that generates reveal.js slide presentations from Lean 4
  documents.
  
- https://verso.lean-lang.org/ the verso website 

- https://github.com/leanprover/verso-templates verso templates and in
  particular a template for slides at
  https://github.com/leanprover/verso-templates/tree/main/slides

- exemplo de slides do Leo em
  https://github.com/leodemoura/ETAPSTutorial2026

### about the content 

- the paper 'Relational Hoare Logic for Realistically Modelled Machine
  Code' at
  https://link.springer.com/chapter/10.1007/978-3-031-98668-0_19 and
  `references/article.pdf`

- previous presentation about the project 'bignum2026.pptx'
