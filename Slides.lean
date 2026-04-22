import VersoSlides
import Verso.Doc.Concrete
open VersoSlides

set_option maxHeartbeats 800000
set_option linter.unusedVariables false
set_option verso.code.warnLineLength 80

#doc (Slides) "Porting s2n-bignum to Lean 4" =>

# Porting s2n-bignum to Lean 4

%%%
backgroundColor := "#0073A3"
%%%

Alexandre Rademaker

FGV/EMAp | CSLib Director at Renaissance Philanthropy

2026


# Part 1: The s2n-bignum Library

%%%
backgroundColor := "#0073A3"
%%%


# What is s2n-bignum?

> s2n-bignum is a collection of integer arithmetic routines designed for cryptographic applications. All routines are written in pure machine code, designed to be callable from C and other high-level languages, with separate but API-compatible versions of each function for 64-bit x86 (x86\_64) and ARM (aarch64).

`github.com/awslabs/s2n-bignum`

Primary goals: *performance* and *assurance*


# What Does It Provide?

- Elementary 64-bit word operations
- Generic bignum arithmetic: addition, subtraction, multiplication, comparison
- Constant-time data manipulation
- Montgomery operations for modular arithmetic
- Optimized operations for elliptic curves:
  - Curve25519, NIST P-256/384/521, secp256k1, SM2


# Formal Verification in HOL Light

Each function ships with a *machine-checked proof* in HOL Light:

- Proves the mathematical result is correct *for all possible inputs*
- Based on a formal model of the underlying processor (ARM or x86)
- The model specifies exactly how each instruction modifies registers, flags, and memory

Not testing — *proof*.


# Two Kinds of Routines

Each operation ships in *two variants*:

| Variant | Goal | Trade-off |
|---|---|---|
| _Optimized_ | Maximum throughput | Hard to verify directly |
| _Verification-friendly_ | Easier to prove | Slower in practice |

The library proves:

1. The optimized version runs in *constant time*
2. Both versions are *functionally equivalent*


# Constant-Time Design

All functions are implemented in *constant time*:

- Execution time depends only on *nominal parameter sizes*
- Never on actual numeric values
- Protects against timing side-channel attacks

> An attacker who can measure execution time must learn nothing
> about secret inputs.


# Library Structure (HOL Light)

```code bash
s2n-bignum/
├── arm/
│   ├── proofs/          # ~150 HOL Light proof files
│   │   ├── bignum_add.ml
│   │   ├── bignum_mul.ml
│   │   └── ...
│   └── tutorial/        # introductory examples
│       ├── simple.ml
│       └── sequence.ml
├── x86/
│   └── proofs/          # x86-64 proofs (similar structure)
└── common/
    └── bignum.ml        # core definitions
```


# Part 2: Why Port to Lean 4?

%%%
backgroundColor := "#0073A3"
%%%


# Why Port to Lean 4?

- HOL Light state-of-the-art, but: OCaml ecosystem, smaller community
- Lean 4 advantages:
  - Same language for *code and proofs* — no translation layer
  - *Mathlib*: 2M+ lines of mathematics, growing fast
  - Active community, modern tooling (Lake, LSP, VS Code)
  - Lean is implemented in Lean — highly extensible
- Goal: make this verification infrastructure accessible to the
  broader Lean community


# Part 3: General Modeling

%%%
backgroundColor := "#0073A3"
%%%


# Machine States

A *state* Σ is a function from observable resources to values:

- ARM: 32 general-purpose registers, flags, memory, program counter
- x86: instruction pointer `rip`, extended flags, memory

```code lean
structure ArmState where
  regs   : Fin 32 → BitVec 64
  pc     : BitVec 64
  flags  : Flags
  memory : Address → Option UInt8
```

Single uniform type — no special cases for different resources.


# Operational Semantics

Execution is *instruction-by-instruction*:

```code lean
def step (s : ArmState) : ArmState :=
  let bytes := s.memory.read s.pc 4
  let instr := decode bytes
  execute instr s
```

Full decode-execute loop, no abstraction over instruction sets.


# Hoare-Style Specifications

We use `ensures` triples — Hoare logic adapted to machine code:

```code lean
def ensures (pre  : ArmState → Prop)
            (prog : List UInt8)
            (post : ArmState → ArmState → Prop) : Prop :=
  ∀ s₀, pre s₀ →
    ∃ s₁, exec prog s₀ = s₁ ∧ post s₀ s₁
```

- *pre*: precondition on initial state
- *post*: relates initial and final state (allows frame reasoning)
- *frame*: memory and registers not mentioned are unchanged


# Compositionality

Programs compose sequentially:

```code lean
theorem ensures_sequence
    (pre mid post : ArmState → Prop)
    (prog₁ prog₂  : List UInt8) :
    ensures pre prog₁ mid →
    ensures mid prog₂ post →
    ensures pre (prog₁ ++ prog₂) post
```

This enables *modular* proofs — verify each chunk independently.


# Part 4: Lean vs HOL Light

%%%
backgroundColor := "#0073A3"
%%%


# Key Differences: Types

| Aspect | HOL Light | Lean 4 |
|---|---|---|
| 64-bit words | `:(64)word` | `BitVec 64` |
| Memory | Component abstraction | `Address → Option UInt8` |
| Natural numbers | HOL `num` | Lean `Nat` (kernel) |
| Proof style | Tactic-only | Tactic + term-mode |
| Ecosystem | `Library/words.ml` | Mathlib `BitVec` |


# Key Differences: Proofs

HOL Light (OCaml meta-language):

```code ocaml
let HIGH_LOW_DIGITS = prove
 (`(!n i. 2 EXP (64 * i) * highdigits n i + lowdigits n i = n)`,
  REWRITE_TAC[highdigits; lowdigits] THEN
  MESON_TAC[DIVISION]);;
```

Lean 4 (same language as definitions):

```code lean
theorem high_low_digits (n i : Nat) :
    2 ^ (64 * i) * highdigits n i + lowdigits n i = n := by
  unfold highdigits lowdigits
  exact Nat.div_add_mod n (2 ^ (64 * i))
```


# HOL Light Correspondence

Every Lean file maps back to its HOL Light source:

```code lean
/--
Corresponds to HOL Light theorem:
  let BIGDIGIT_HIGHDIGITS = prove
   (`!n i j. bigdigit (highdigits n i) j = bigdigit n (i + j)`, ...);;
Source: s2n-bignum/common/bignum.ml:164-167
-/
theorem bigdigit_highdigits (n i j : Nat) :
    bigdigit (highdigits n i) j = bigdigit n (i + j) := by
  unfold bigdigit highdigits
  rw [Nat.mul_add, Nat.pow_add, Nat.div_div_eq_div_mul]
```

Line-by-line traceability maintained throughout.


# Lean Project Structure

```code bash
bignum-lean/
├── Bignum/
│   ├── Common/
│   │   ├── Basic/
│   │   │   ├── Defs.lean       # bigdigit, highdigits, lowdigits
│   │   │   └── Lemmas.lean     # core theorems (complete)
│   │   ├── Word.lean           # BitVec 64 arithmetic
│   │   └── Memory.lean         # memory model
│   └── Arm/
│       ├── Machine/            # State, Instruction, Decode, Loader
│       ├── Spec.lean           # ensures + operational semantics
│       ├── Tactic.lean         # proof automation
│       └── Tutorial/           # Simple.lean, Sequence.lean
└── s2n-bignum/                 # original HOL Light (git submodule)
```


# Part 5: Two Tutorials

%%%
backgroundColor := "#0073A3"
%%%


# Tutorial 1: Simple

Port of `s2n-bignum/arm/tutorial/simple.ml` — two instructions:

```code asm
add x2, x1, x0    -- x2 := x1 + x0
sub x2, x2, x1    -- x2 := x2 - x1
```

*Claim*: starting with `X0 = a`, `X1 = b`, we end with `X2 = a`.

```code lean
theorem simple_correct (s : ArmState) ... :
    ensures
      (fun s => s.regs X0 = a ∧ s.regs X1 = b)
      simple_mc
      (fun _ s' => s'.regs X2 = a)
```


# Tutorial 1: What We Learn

- *Loading bytes*: from `simple_mc : List UInt8`
- *Decoding*: bytes → `Instruction` via `Decode.lean`
- *Simulation*: `exec simple_mc s₀` gives the final state
- *Frame conditions*: all other registers/memory unchanged
- *`ensures_of_exec`*: reduces proof to decode + post + frame

Corresponds to ~30 lines of Lean vs ~40 lines of HOL Light.


# Tutorial 2: Sequence

Port of `s2n-bignum/arm/tutorial/sequence.ml` — four instructions:

```code asm
add x1, x1, x0    -- x1 := x1 + x0
add x2, x2, x0    -- x2 := x2 + x0
mov x3, #2
mul x1, x1, x3    -- x1 := x1 * 2
```

*Key technique*: compositional verification via `ensures_sequence`

1. Split at `pc+8` into two chunks
2. Prove intermediate assertion: `X1 = a + b`
3. Compose results with `ensures_sequence`


# Tutorial 2: What We Learn

- *`ensures_sequence`*: sequential composition of proofs
- *Intermediate assertions*: explicit intermediate state
- *`ensures_of_exec`*: each chunk proved independently

Original HOL Light: ~185 lines (manual `eventually.ind`)

Lean port with `ensures_of_exec`: significantly shorter,
proofs read more directly as specifications.


# Part 6: Next Steps

%%%
backgroundColor := "#0073A3"
%%%


# Next Steps

*1. Port ARM arithmetic algorithm proofs*

- `bignum_add`, `bignum_mul`, `bignum_sub`, modular reduction, ...
- The infrastructure (Spec, Tactic, Decode) is in place
- This is the main pending work

*2. x86-64 support*

- Mirror the ARM machine model for x86-64
- Port the x86 proofs from s2n-bignum

*3. Relational verification*

- Constant-time proofs (`compare` vs `cst-compare`)
- Functional equivalence between optimized and verification-friendly routines

*4. High-level integration*

- Connect to Mathlib number theory
- End-to-end proofs from algorithm to assembly


# Thank You

%%%
backgroundColor := "#0073A3"
%%%

*Alexandre Rademaker*

Atlas Computing | FGV/EMAp

`github.com/atlas-computing-org/bignum`

`admin@atlascomputing.org`
