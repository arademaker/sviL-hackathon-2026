import VersoSlides
import Verso.Doc.Concrete
import Bignum.Arm.Machine.State
import Bignum.Arm.Spec
open VersoSlides
open Bignum Bignum.Arm

set_option maxHeartbeats 800000
set_option linter.unusedVariables false
set_option verso.code.warnLineLength 80

#doc (Slides) "Porting s2n-bignum to Lean 4" =>

```css
table.slide-table {
  width: 100% !important;
  max-width: 100% !important;
  margin: 0.5em 0 !important;
}
.reveal pre {
  align-self: center !important;
  width: fit-content !important;
  max-width: 80% !important;
  margin: 0.5em 0 !important;
}
```

# Porting s2n-bignum to Lean 4

%%%
backgroundColor := "#0073A3"
%%%

Alexandre Rademaker

FGV/EMAp | CSLib at Renaissance Philanthropy

INRIA Paris 2026


# Part 1: The s2n-bignum Library

%%%
backgroundColor := "#0073A3"
%%%


# What is s2n-bignum?

> s2n-bignum is a collection of integer arithmetic routines designed for cryptographic applications. All routines are written in pure machine code, designed to be callable from C and other high-level languages, with separate but API-compatible versions of each function for 64-bit x86 (x86\_64) and ARM (aarch64).

[https://github.com/awslabs/s2n-bignum](https://github.com/awslabs/s2n-bignum)

Primary goals: *performance* and *assurance*


# What Does It Provide?

- Elementary 64-bit word operations
- Generic bignum arithmetic: addition, subtraction, multiplication, comparison
- Constant-time data manipulation
- Montgomery operations for modular arithmetic
- Optimized operations for elliptic curves:
  - Curve25519, NIST P-256/384/521, secp256k1, SM2


# Constant-Time Design

> The actual sequence of machine instructions executed, including the specific addresses and sequencing of memory loads and stores, is *independent of the numbers themselves*, depending only on their *nominal sizes*.

Consequences:

- No stripping of leading zeros, no dynamic memory allocation
- Results that do not fit are *truncated modulo* the output size
- Sizes are explicit parameters — fixed at call time

```code c
void bignum_mul(uint64_t p, uint64_t *z,
                uint64_t m, uint64_t *x,
                uint64_t n, uint64_t *y);
```

`x` is an `m`-digit bignum, `y` is `n`-digit; result written to `p`-word buffer `z`.


# Formal Verification in HOL Light

Each function ships with a *machine-checked proof* in HOL Light:

- Proves the mathematical result is correct
- Based on a formal model of the underlying processor (ARM or x86)
- The model specifies exactly how each instruction modifies registers, flags, and memory

Two logics, both mechanized in HOL Light:

- *L1* (unary): functional correctness via Hoare triples — `eventually` operator, ~860K lines of proofs covering 600+ routines. It is implemented in 10k lines of HOL Light.
- *L2* (relational): extends L1 with step-counting `eventually` to prove *constant-time* behavior and equivalence between optimized and reference implementations. The core of the relational verification amounts to 1704 lines of code.


# Why is this relevant?

- [Relational Hoare Logic for Realistically Modelled Machine Code](https://link.springer.com/chapter/10.1007/978-3-031-98668-0_19).
- [Formal verification makes RSA faster — and faster to deploy](https://www.amazon.science/blog/formal-verification-makes-rsa-faster-and-faster-to-deploy)
- [Better-performing “25519” elliptic-curve cryptography](https://www.amazon.science/blog/better-performing-25519-elliptic-curve-cryptography)
- Dan J. Bernstein (creator of elliptic curve Curve25519) ["OpenSSL/BoringSSL must use s2n-bignum!"](https://youtu.be/iQzKFy6avIw?si=ahk5xEQY4rPDOpVC)


# Library Structure (HOL Light)

```code bash
s2n-bignum/
├── arm/
│   ├── proofs/          # ~351 HOL Light files
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

# Why HOL Light?

- Because [John Harrison](https://www.cl.cam.ac.uk/~jrh13/) is the creator of HOL Light!
- HOL Light is an interactive theorem prover, like Lean

# Verifying Assembly in s2n-bignum

{image "static/s2n-bignum.jpg" (width := "90%")}[Verification pipeline: assembly source to HOL Light proof]

# Why Port to Lean 4?

- Lean 4 advantages:
  - Same language for *code and proofs* — no translation layer
  - *Mathlib*: 2M+ lines of mathematics, growing fast
  - Active community, modern tooling (Lake, LSP, VS Code)
  - Lean is implemented in Lean — highly extensible
  - Performance
- Goal: make this verification infrastructure accessible to the broader Lean community


# Part 3: General Model

%%%
backgroundColor := "#0073A3"
%%%

# ARM model

%%%
vertical := some true
%%%

## Machine State

32 general-purpose registers, flags, memory, program counter

```lean
-- !hide
namespace Slide
-- !end hide
public abbrev Word64 := BitVec 64
abbrev Address := Word64
def Memory := Address → Option UInt8

inductive Reg
  | X  : Fin 31 → Reg  -- X0–X30
  | PC : Reg
  | SP : Reg

structure ArmState where
  regs  : /- !replace Slide.Reg -/ Reg /- !end replace -/ → Word64
  flags : Flags
  mem   : Memory
-- !hide
end Slide
-- !end hide
```


## Decode-Execute Pipeline

```code text
 Memory (List UInt8)
         │
         ▼
 arm_decode (Spec.lean)          -- reads 4 bytes at PC
   └─→ decode : UInt32 →         -- Decode.lean
         Option Instruction
         │
         ▼
 step : Instruction →            -- Instruction.lean
          ArmState → ArmState
   ├─→ read_reg / write_reg      -- State.lean
   └─→ advance_pc
         │
         ▼
 exec : List Instruction →       -- folds step over list
          ArmState → ArmState
         │
         ▼
 arm : ArmState → ArmState →     -- single-step relation
         Prop                    -- used in ensures triples
```

`ensures_of_exec` bridges `exec` and `arm`, reducing Hoare
proofs to: (1) decode, (2) post-condition, (3) frame.

## ARM Instruction Semantics

Execution is *instruction-by-instruction*:

```code lean
def advance_pc (s : ArmState) (s' : ArmState) : ArmState :=
  s'.write_reg Reg.PC (s.read_reg Reg.PC + 4)

def step (instr : Instruction) (s : ArmState) : ArmState :=
  match instr with
  | Instruction.ADD rd rn rm =>
    -- Xd := Xn + Xm (word addition, no flags)
    let val_n := s.read_reg rn
    let val_m := s.read_reg rm
    let result := val_n + val_m  -- BitVec addition (wraps at 2^64)
    advance_pc s (s.write_reg rd result)
  ...
```

# Hoare-Style Specifications

We use `ensures` triples — Hoare logic adapted to machine code:

```lean
-- !hide
namespace Slide
-- !end hide
def ensures (step : α → α → Prop) (pre post : α → Prop)
  (frame : α → α → Prop) : Prop :=
  ∀ s, pre s → eventually step
    (fun s' => post s' ∧ frame s s') s
-- !hide
end Slide
-- !end hide
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

# Key Differences: Proofs

HOL Light (OCaml meta-language):

```code ocaml
let HIGH_LOW_DIGITS = prove
 (`(!n i. 2 EXP (64 * i) * highdigits n i + lowdigits n i = n) /\
   (!n i. lowdigits n i + 2 EXP (64 * i) * highdigits n i = n) /\
   (!n i. highdigits n i * 2 EXP (64 * i) + lowdigits n i = n) /\
   (!n i. lowdigits n i + highdigits n i * 2 EXP (64 * i) = n)`,
  REWRITE_TAC[lowdigits; highdigits] THEN
  MESON_TAC[DIVISION_SIMP; ADD_SYM; MULT_SYM]);;
```

Lean 4 (same language as definitions):

```lean
theorem high_low_digits (n i : Nat)
  : 2 ^ (64 * i) * highdigits n i + lowdigits n i = n
  := by
  unfold highdigits lowdigits
  exact Nat.div_add_mod n (2 ^ (64 * i))
```


# HOL Light Correspondence

Every Lean file maps back to its HOL Light source:

```lean
/--
If n is bounded, then highdigits n i = 0.

Source: s2n-bignum/common/bignum.ml:113-115
-/
theorem highdigits_of_lt (n i : Nat) (h : n < 2 ^ (64 * i)) :
    highdigits n i = 0 := by
  rw [highdigits_eq_zero]
  exact h
```

# Lean Project Structure

```code text
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

Port of `s2n-bignum/arm/tutorial/simple.ml`

```code asm
0:   8b000022        add     x2, x1, x0
4:   cb010042        sub     x2, x2, x1
```

# Tutorial 1: The Claim

Starting with `X0 = a`, `X1 = b`, after both instructions: `X2 = a`.  Only `PC` and `X2` change.

```code lean
theorem SIMPLE_SPEC (pc a b : ℕ) :
    ensures arm
      (fun s => aligned_bytes_loaded s.mem (BitVec.ofNat 64 pc) simple_mc ∧
                s.read_reg Reg.PC = BitVec.ofNat 64 pc ∧
                s.read_reg Reg.X0 = BitVec.ofNat 64 a ∧
                s.read_reg Reg.X1 = BitVec.ofNat 64 b)
      (fun s => s.read_reg Reg.PC = BitVec.ofNat 64 (pc + 8) ∧
                s.read_reg Reg.X2 = BitVec.ofNat 64 a)
      (maychange_regs [Reg.PC, Reg.X2]) := by
```

# Tutorial 1: Proof Strategy

- 1. Decode: bytes → Instruction list (2 lines)
- 2. Post: postcondition holds after exec (10 lines)
- 3. Frame: other registers unchanged (5 lines)

# Tutorial 2: Sequence

Port of `s2n-bignum/arm/tutorial/sequence.ml`

```code asm
0:   8b000021        add     x1, x1, x0
4:   8b000042        add     x2, x2, x0
8:   d2800043        mov     x3, #0x2
c:   9b037c21        mul     x1, x1, x3
```

# Tutorial 2: The Approach

1. Split at pc+8 into two chunks:
   - First chunk (pc to pc+8): two `add` instructions
   - Second chunk (pc+8 to pc+16): `mov` and `mul`

2. Intermediate assertion at pc+8: `X1 = a + b`

3. Prove each chunk with `ensures_of_exec`, compose with `ensures_sequence`.

# Tutorial 2: Proof by Composition

```code lean
theorem sequence_correct (pc a b c : ℕ) :
    ensures arm
      (sequence_pre pc a b c)
      (sequence_post pc a b)
      (maychange_regs [Reg.PC, Reg.X1, Reg.X2, Reg.X3]) :=
  ensures_sequence _ _ _
    (maychange_regs [Reg.PC, Reg.X1, Reg.X2, Reg.X3])
    (sequence_chunk1_correct pc a b c)
    (sequence_chunk2_correct pc a b)
    (maychange_regs_trans _)
```

Original HOL Light: ~185 lines. Lean port: ~100 lines.


# Part 6: Next Steps

%%%
backgroundColor := "#0073A3"
%%%

# Conclusion

- First version of ARM architecture
- First two tutorials completed
- Building the Lean project is faster than load HOL Light

# High-level integration

- Connect to CSLib
- Connect to Mathlib
- End-to-end proofs from algorithm to assembly

# Next Steps

1. Port ARM arithmetic algorithm proofs
   - `bignum_add`, `bignum_mul`, `bignum_sub`, modular reduction...
   - Revise infrastructure (Spec, Tactic, Decode) in place

2. x86-64 support
   - Adapt the ARM machine model for x86-64
   - Port the x86 proofs from s2n-bignum

3. Relational verification (see the [paper](https://link.springer.com/chapter/10.1007/978-3-031-98668-0_19))
   - Constant-time proofs
   - Functional equivalence between optimized and verification-friendly routines


# Thank You

%%%
backgroundColor := "#0073A3"
%%%

*Alexandre Rademaker*

FGV/EMAp | CSLib

`github.com/atlas-computing-org/bignum`

`arademaker@gmail.com`
