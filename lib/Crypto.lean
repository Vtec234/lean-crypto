import Crypto.ByteBuffer
import Crypto.ByteVec2
import Crypto.Matrix
import Crypto.UInt8
import Crypto.Vector

namespace Bool

protected def xor (x y : Bool) : Bool := if x then not y else y

instance : Xor Bool := ⟨Bool.xor⟩

end Bool

def BitVec (n:Nat) := Fin (2^n)

--structure BitVec (n:Nat) where
--  val : Nat
--  isLt : val < 2^n

namespace BitVec

protected def zero (n:Nat) : BitVec n := ⟨0, sorry⟩

instance : Inhabited (BitVec n) := ⟨BitVec.zero n⟩

protected def append {m n:Nat} (x:BitVec m) (y:BitVec n) : BitVec (m+n) :=
  ⟨x.val <<< n ||| y.val, sorry⟩

instance : HAppend (BitVec m) (BitVec n) (BitVec (m+n)) where
  hAppend := BitVec.append

protected def and (x y : BitVec n) : BitVec n := ⟨x.val &&& y.val, sorry⟩
protected def or  (x y : BitVec n) : BitVec n := ⟨x.val ||| y.val, sorry⟩
protected def xor (x y : BitVec n) : BitVec n := ⟨x.val ^^^ y.val, sorry⟩

instance : AndOp (BitVec n) := ⟨BitVec.and⟩
instance : OrOp (BitVec n) := ⟨BitVec.or⟩
instance : Xor (BitVec n) := ⟨BitVec.xor⟩

def lsb_get! {m:Nat} (x:BitVec m) (i:Nat) : Bool :=
  (x.val &&& (1 <<< i)) ≠ 0

def lsb_set! {m:Nat} (x:BitVec m) (i:Nat) (c:Bool) : BitVec m :=
  if c then
    x ||| ⟨1 <<< i, sorry⟩
  else
    x &&& ⟨((1 <<< m) - 1 - (1 <<< i)), sorry⟩

/-
def msb_fix (m:Nat) (i:Nat) : Nat := (m-1)-i

def msb_get! {m:Nat} (x:BitVec m) (i:Nat) : Bool := x.lsb_get! (msb_fix m i)

def msb_set! {m:Nat} (x:BitVec m) (i:Nat) (c:Bool) : BitVec m :=
  x.lsb_set! (msb_fix m i) c
-/

def msbb_fix (m:Nat) (i:Nat) : Nat :=
  let j := (m-1)-i
  -- Reverse bit order within bytes (see if we can fix this)
  ((j >>> 3) <<< 3) ||| (0x7 - (j &&& 0x7))

def msbb_get! {m:Nat} (x:BitVec m) (i:Nat) : Bool := x.lsb_get! (msbb_fix m i)

def msbb_set! {m:Nat} (x:BitVec m) (i:Nat) (c:Bool) : BitVec m :=
  x.lsb_set! (msbb_fix m i) c

protected def toBinary (x:BitVec n) : String :=
  let l := Nat.toDigits 2 x.val
  String.mk (List.replicate (n - l.length) '0' ++ l)

protected def toHex (x:BitVec n) : String :=
  let l := Nat.toDigits 16 x.val
  String.mk (List.replicate (n/4 - l.length) '0' ++ l)

protected def toHex2 (x:BitVec n) : String := Id.run do
  let mut s : String := ""
  for i in range 0 (n/8) do
    let b := UInt8.ofNat (x.val >>> (8*i))
    s := s ++ b.toHex
  pure s
instance : ToString (BitVec n) := ⟨BitVec.toHex2⟩

def reverse (x:BitVec n) : BitVec n := Id.run do
  let mut r : Nat := 0
  for i in range 0 n do
    r := r <<< 1
    if x.lsb_get! i then
      r := r + 1
  pure ⟨r, sorry⟩


protected def foldl (f: α → Bool → α) (x: BitVec n) (a : α) : α := Id.run do
  let mut r := a
  for i in range 0 n do
    r := f r (x.msbb_get! i)
  pure r

protected def take_lsb (x:BitVec m) (n:Nat) : BitVec n :=
  ⟨x.val &&& 1 <<< n - 1, sorry⟩

protected def take_msb (x:BitVec m) (n:Nat) : BitVec n :=
  ⟨x.val >>> (m-n), sorry⟩

theorem eq_of_val_eq {n:Nat} : ∀ {x y : BitVec n}, Eq x.val y.val → Eq x y
  | ⟨x,_⟩, _, rfl => rfl

theorem ne_of_val_ne {n:Nat}  {i j : BitVec n} (h : Not (Eq i.val j.val)) : Not (Eq i j) :=
  λh' => absurd (h' ▸ rfl) h

protected def decideEq {n:Nat} : (a b : BitVec n) → Decidable (Eq a b) :=
  fun ⟨i, _⟩ ⟨j, _⟩ =>
    match decEq i j with
    | isTrue h  => isTrue (eq_of_val_eq h)
    | isFalse h => isFalse (ne_of_val_ne h)

instance (n:Nat) : DecidableEq (BitVec n) := BitVec.decideEq

end BitVec

@[extern "lean_elt_from_bytevec"]
constant eltFromByteVec {w:Nat} (r:Nat) (v:ByteVec w) : BitVec r

@[extern "lean_elt_to_bytevec"]
constant eltToByteVec {r:Nat} (w:Nat) (v:BitVec r) : ByteVec w

def ByteVec.toBuffer {n:Nat} : ByteVec n → ByteBuffer
| ⟨a,_⟩ => ⟨a⟩

instance : Coe (ByteVec n) ByteBuffer where
  coe := ByteVec.toBuffer

structure DRBG where
  key : ByteVec (256 / 8)
  v : ByteVec (128 / 8)

instance : Inhabited DRBG := ⟨Inhabited.default, Inhabited.default⟩

def tryN {α:Type _ } (f:DRBG → Option α × DRBG)
     : ∀(drbg:DRBG) (attempts:Nat), Option α × DRBG
  | drbg, 0 =>
    (none, drbg)
  | drbg, Nat.succ attempts =>
    match f drbg with
    | (some ind, drbg) => (some ind, drbg)
    | (none, drbg) => tryN f drbg attempts

@[reducible]
def Seed := ByteVec 48

@[extern "lean_random_init"]
constant randombytesInit : @&Seed → DRBG

@[extern "lean_random_bytes"]
constant randombytes (rbg:DRBG) (n:@&Nat) : ByteVec n × DRBG

def initKeypairSeedPrefix : ByteVec 1 := #v[64]

def initKeypairSeed (v:ByteVec 32) : ByteVec 33 := initKeypairSeedPrefix ++ v

@[extern "lean_shake256"]
constant shake (w:Nat) (input: ByteArray) : ByteVec w

def cryptoHash32b (b:ByteArray) : ByteVec 32 := shake 32 b

namespace Mceliece348864Ref

def name : String := "mceliece348864"

def N := 3488

@[reducible]
def gfbits : Nat := 12

@[reducible]
def sys_t : Nat := 64

@[reducible]
def cond_bytes : Nat := (1 <<< (gfbits-4))*(2*gfbits - 1)

@[reducible]
def pk_nrows : Nat := sys_t * gfbits

@[reducible]
def pk_ncols : Nat := N - pk_nrows

def publicKeyBytes : Nat := pk_nrows * (pk_ncols / 8)

def PublicKey := Vector pk_nrows (BitVec pk_ncols)

namespace PublicKey

def pk_row_bytes : Nat := pk_ncols / 8

-- Create public key from row matrix
def init (m : Matrix pk_nrows (N/8) UInt8) : PublicKey :=
  Vector.generate pk_nrows λr =>
    let v := ByteVec.generate (pk_ncols / 8) (λc => m.get! r (pk_nrows/8 + c))
    eltFromByteVec pk_ncols v

-- Create public key from row matrix
def init2 (m : Vector pk_nrows (BitVec N)) : PublicKey :=
  Vector.generate pk_nrows λr =>
    (m.get! r).take_msb pk_ncols

protected
def toBytes (pk:PublicKey) : ByteVec Mceliece348864Ref.publicKeyBytes :=
  let v := (eltToByteVec (pk_ncols / 8)) <$> pk
  ByteVec.generate publicKeyBytes λi =>
    let r := i.val / pk_row_bytes
    let c := i.val % pk_row_bytes
    (v.get! r).get! c

protected def toString (pk:PublicKey) : String := pk.toBytes.toString

instance : ToString PublicKey := ⟨PublicKey.toString⟩

end PublicKey

@[reducible]
def GF := { x:UInt16 // x < (1<<<12) }

def gfMask : UInt16 := (1 <<< 12) - 1

namespace GF

instance : Inhabited GF := ⟨⟨0, sorry⟩⟩

protected def complement (x:GF) : GF := ⟨~~~x.val, sorry⟩
protected def and (x y:GF) : GF := ⟨x.val &&& y.val, sorry⟩
protected def or  (x y:GF) : GF := ⟨x.val ||| y.val, sorry⟩
protected def xor  (x y:GF) : GF := ⟨x.val ^^^ y.val, sorry⟩

@[extern "lean_gf_add"]
protected constant add (x y : GF) : GF

@[extern "lean_gf_mul"]
protected constant mul (x y : GF) : GF

instance : Complement GF := ⟨GF.complement⟩
instance : AndOp GF := ⟨GF.and⟩
instance : OrOp GF := ⟨GF.or⟩
instance : Xor GF := ⟨GF.xor⟩
instance : Add GF := ⟨GF.add⟩
instance : Mul GF := ⟨GF.mul⟩

instance (n:Nat) : OfNat GF n := { ofNat := ⟨UInt16.ofNat n &&& gfMask, sorry⟩ }

end GF

@[extern "lean_gf_iszero"]
constant gf_iszero : GF -> GF

@[extern "lean_gf_inv"]
constant gf_inv : GF -> GF

@[extern "lean_bitrev"]
constant gf_bitrev : GF -> GF

def loadGf {n} (r: ByteVec n) (i:Nat) : GF :=
  let f (x:UInt8) : UInt16 := UInt16.ofNat x.toNat
  let w : UInt16 := f (r.get! (i+1)) <<< 8 ||| f (r.get! i)
  ⟨w &&& gfMask, sorry⟩

def loadGfArray {n:Nat} (r: ByteVec (2*n)) : Vector n GF :=
  Vector.generate n (λi => loadGf r (2*i.val))

@[extern "lean_store_gf"]
constant store_gf (irr : Vector sys_t GF) : ByteVec (2*sys_t)

def secretKeyBytes : Nat := 40 + 2*sys_t + cond_bytes + N/8

@[reducible]
structure SecretKey where
  seed : ByteVec 32
  goppa : Vector sys_t GF
  controlbits : ByteVec cond_bytes
  rest : ByteVec (N/8)

namespace SecretKey

def byteVec (sk:SecretKey) : ByteVec Mceliece348864Ref.secretKeyBytes :=
  sk.seed
    ++ ByteVec.ofUInt64lsb 0xffffffff
    ++ store_gf sk.goppa
    ++ sk.controlbits
    ++ sk.rest

protected def toString (sk:SecretKey) : String := sk.byteVec.toString

--protected def toString (sk:SecretKey) : String :=
--  sk.seed.toString
--    ++ "ffffffff00000000"
--    ++ toString (store_gf sk.goppa)
--    ++ sk.controlbits.toString
--    ++ sk.rest.toString

instance : ToString SecretKey := ⟨SecretKey.toString⟩

end SecretKey

structure KeyPair where
  pk : PublicKey
  sk : SecretKey

@[reducible]
def rw : Nat :=  N/8 + 4*(1 <<< gfbits) + sys_t * 2 + 32

def byteToUInt32 (v:UInt8) : UInt32 := UInt32.ofNat (v.toNat)

def load4 {n} (r: ByteVec n) (i:Nat) : UInt32 :=
  let b (j:Nat) (s:UInt32) : UInt32 := byteToUInt32 (r.get! (i+j)) <<< s
  b 0 0 ||| b 1 8 ||| b 2 16 ||| b 3 24

def load4Array {n:Nat} (r: ByteVec (4*n)) : Vector n UInt32 :=
  Vector.generate n (λi => load4 r (4*i.val))


@[extern "lean_GF_mul"]
constant GF_mul (x y : Vector sys_t GF) : Vector sys_t GF

def genPolyGen_mask (mat : Matrix (sys_t+1) sys_t GF) (j:Nat) : GF := Id.run do
  let mut r := mat.get! j j
  for i in rangeH j (sys_t+1) do
    for k in rangeH (j+1) sys_t do
      r := r ^^^ mat.get! i k
  pure r

def genPolyGenUpdate (mat : Matrix (sys_t+1) sys_t GF)
                         (j : Nat)
                         (inv : GF)
                        : Matrix (sys_t+1) sys_t GF :=
  Matrix.generate _ _ λr c =>
    if r ≤ j then
      0
    else
      if c = j then
        inv * mat.get! r j
      else
        mat.get! r c ^^^ (inv * mat.get! r j * mat.get! j c)

def genPolyGen (f : Vector sys_t GF) : Option (Vector sys_t GF) := Id.run do
  let v0 : Vector sys_t GF := Vector.generate sys_t λi => if i = 0 then 1 else 0
  let mut mat := Matrix.unfoldBy (GF_mul f) v0
  for j in range 0 sys_t do
    let r0 := mat.get! j j
    let r := genPolyGen_mask mat j
    let mask := gf_iszero r0
    let r := r0 &&& ~~~mask ||| r &&& mask
    if r = 0 then
      return none
    else
      mat := genPolyGenUpdate mat j (gf_inv r)
  some (mat.row! sys_t)

-- Map used by init_pi
structure Perm where
  value : UInt32
  idx : GF

namespace Perm

instance : Inhabited Perm := ⟨{ value := 0, idx := 0}⟩

end Perm

-- Generate random permutation from random uint32 array
def randomPermutation (perm : Vector (1 <<< gfbits) UInt32)
  : Option (Vector (1 <<< gfbits) GF) := Id.run do
  -- Build vector associated input number to index
  let v : Vector (1 <<< gfbits) Perm :=
        Vector.generate _
          (λi => { value := perm.get i, idx := OfNat.ofNat i.val })

  -- Sort vector based on value to get random permutation
  let lt (x y : Perm) : Bool := x.value < y.value
  let v : Vector (1 <<< gfbits) Perm := Vector.qsort v lt

  -- Check to see if we have duplicated values in sorted array
  -- Failing to check can bias result
  for i in range 0 (1 <<< gfbits - 1) do
    if (v.get! i).value = (v.get! (i+1)).value then
      return none

  pure (some (Perm.idx <$> v))

@[extern "lean_eval"]
constant eval (sk : Vector (sys_t+1) GF) (x : GF) : GF

@[extern "lean_init_mat"]
constant init_mat (inv : @&(Vector N GF)) (L : @&(Vector N GF))
  : Matrix pk_nrows (N/8) UInt8

@[extern "lean_init_mat2"]
constant init_mat2 (inv : @&(Vector N GF)) (L : @&(Vector N GF))
  : Vector pk_nrows (BitVec N)

@[extern "lean_gaussian_elim_row"]
constant gaussian_elim_row (m : @&(Matrix pk_nrows (N/8) UInt8)) (r: Nat)
  : Option (Matrix pk_nrows (N/8) UInt8)

@[extern "lean_gaussian_elim_row2"]
constant gaussian_elim_row2 (m : @&(Vector pk_nrows (BitVec N))) (row: Nat)
  : Option (Vector pk_nrows (BitVec N))

--@[extern "lean_gaussian_elim_row"]
def gaussian_elim_row3 (m : @&(Vector pk_nrows (BitVec N))) (row: Nat)
  : Option (Vector pk_nrows (BitVec N)) := Id.run do
  let mut mat_row := m.get! row
  for k in rangeH (row+1) pk_nrows do
    let mat_k := m.get! k
    let mask1 := mat_row.msbb_get! row
    let mask2 := mat_k.msbb_get! row
    if mask1 ≠ mask2 then
      mat_row := mat_row ^^^ mat_k
  if not (mat_row.msbb_get! row) then
    return none
  let mut m := m
  for k in range 0 pk_nrows do
    if k = row then
      m := m.set! k mat_row
    else
      let mat_k := m.get! k
      if mat_k.msbb_get! row then
        m := m.set! k (mat_k ^^^ mat_row)
  pure (some m)


def gaussian_elim (m : @&(Matrix pk_nrows (N/8) UInt8))
  : Option (Matrix pk_nrows (N/8) UInt8) := Id.run do
  let mut m := m
  for i in range 0 pk_nrows do
    match gaussian_elim_row m i with
    | some m' => m := m'
    | none => return none
  pure (some m)

def gaussian_elim2 (m : Vector pk_nrows (BitVec N))
  : Option (Vector pk_nrows (BitVec N)) := Id.run do
  let mut m := m
  for i in range 0 pk_nrows do
    match gaussian_elim_row2 m i with
    | some m1 =>
      m := m1
    | none => return none
  pure (some m)

@[extern "lean_controlbitsfrompermutation"]
constant controlBitsFromPermutation (pi : Vector (1 <<< gfbits) GF) : ByteVec cond_bytes

def tryCryptoKemKeypair (seed: ByteVec 32) (r: ByteVec rw) : Option KeyPair := do
  let g ← genPolyGen $ loadGfArray $ r.extractN (N/8 + 4*(1 <<< gfbits)) (2*sys_t)
  let pi  ← randomPermutation $ load4Array $ r.extractN (N/8) (4*(1 <<< gfbits))
  let L   := Vector.generate N λi => gf_bitrev (pi.get! i)
  let g' := g.push 1
  let inv := (λx => gf_inv (eval g' x)) <$> L
  let pk := PublicKey.init (← gaussian_elim (init_mat inv L))
  let sk := { seed := seed,
              goppa := g,
              controlbits := controlBitsFromPermutation pi
              rest := r.extractN 0 (N/8)
            }
  some ⟨pk, sk⟩

def mkCryptoKemKeypair (iseed : Seed) (attempts: optParam Nat 10) : Option (KeyPair × DRBG) := do
  let rec loop : ∀(seed: ByteVec 32) (attempts:Nat), Option KeyPair
      | _, 0 => none
      | seed, Nat.succ n => do
        let r := shake rw (#v[64] ++ seed).data
        match tryCryptoKemKeypair seed r with
        | some kp => some kp
        | none =>
          loop (r.takeFromEnd 32) n
  let drbg := randombytesInit iseed
  let (bytes, drbg) := randombytes drbg 32
  match loop bytes attempts with
  | none => none
  | some p => some (p, drbg)

def tryGenerateRandomErrors (v : Vector (2*sys_t) GF) (n:Nat) : Option (Vector n (Fin N)) := Id.run do
  let mut ind : Array (Fin N) := Array.mkEmpty sys_t
  for num in v.data do
    let num := num.val.toNat
    if lt : num < N then
      ind := ind.push ⟨num, lt⟩
      if eq:ind.size = n then
        return (some ⟨ind, eq⟩)
  pure none

def has_duplicate {n:Nat} {α:Type} [DecidableEq α] (v: Vector n α) : Bool := Id.run do
  for i in rangeH 1 n do
    for j in range 0 i do
      if lt_i : i < n then
        if lt_j : j < n then
          if v.get ⟨i, lt_i⟩ = v.get ⟨j, lt_j⟩ then
            return true
  pure false

def generateErrorBitmask (a: Vector sys_t (Fin N)) : BitVec N := Id.run do
  let mut e : BitVec N := BitVec.zero N
  for v in a.data do
    e := e.msbb_set! v.val true
  pure e

def tryGenerateErrors (drbg:DRBG) : Option (BitVec N) × DRBG := Id.run do
  let (bytes, drbg) := randombytes drbg (4*sys_t)
  let input : Vector (2*sys_t) GF := loadGfArray bytes

  let mut a : Array (Fin N) := Array.mkEmpty sys_t
  for (num : GF) in input.data do
    let num : Nat := num.val.toNat
    if lt : num < N then
      a := a.push ⟨num, lt⟩
      -- Check to see if done
      if eq:a.size = sys_t then
        let v : Vector sys_t (Fin N) := ⟨a, eq⟩
        if has_duplicate v then
          return (none, drbg)
        return (some (generateErrorBitmask v), drbg)
  pure ⟨none, drbg⟩

def cSyndrome (pk : PublicKey) (e: BitVec N) : BitVec pk_nrows := Id.run do
  let mut s : BitVec pk_nrows := BitVec.zero _
  for i in range 0 pk_nrows do
    let off := (BitVec.zero pk_nrows).msbb_set! i True
    let row : BitVec N := off ++ pk.get! i
    if (row &&& e).foldl Bool.xor false then
      s := s.msbb_set! i True
  pure s

@[reducible]
structure Ciphertext where
  syndrome : BitVec pk_nrows
  hash : ByteVec 32

namespace Ciphertext

protected def bytes (c:Ciphertext) : ByteVec 128 :=
  eltToByteVec (pk_nrows/8) c.syndrome ++ c.hash

protected def toString (c:Ciphertext) : String := c.bytes.toString

instance : ToString Ciphertext := ⟨Ciphertext.toString⟩

def mkHash (e:BitVec N) : ByteVec 32 :=
  cryptoHash32b (#b[2].data ++ (eltToByteVec (N/8) e).data)

end Ciphertext

structure Plaintext where
  e : BitVec N
  c : Ciphertext

namespace Plaintext

protected def bytes (p:Plaintext) :  ByteVec 32 :=
  cryptoHash32b (#b[1].data ++ (eltToByteVec (N/8) p.e).data ++ p.c.bytes.data)

protected def toString (p:Plaintext) : String := p.bytes.toString

instance : ToString Plaintext := ⟨Plaintext.toString⟩

end Plaintext

structure EncryptionResult where
  ss : Plaintext
  ct : Ciphertext

def mkCryptoKemEnc (drbg:DRBG) (attempts:Nat) (pk:PublicKey) : Option (EncryptionResult × DRBG) := do
  match tryN tryGenerateErrors drbg attempts with
  | (some e, drbg) =>
    let c   := { syndrome := cSyndrome pk e,
                 hash := Ciphertext.mkHash e
                }
    let plaintext := { e := e, c := c }
    some ({ ss := plaintext, ct := c }, drbg)
  | (none, _) => panic! "mkCryptoKemEnc def failure"

@[extern "lean_support_gen"]
constant support_gen (controlbits : @&(ByteVec cond_bytes)) : Vector N GF

def synd
    (g: @&(Vector sys_t GF))
    (l : @&(Vector N GF))
    (error_bitmask : @&(BitVec N))
   : Vector (2*sys_t) GF := Id.run do
  let mut out := Vector.replicate (2*sys_t) 0
  let f := g.push 1
  for i in range 0 N do
    if error_bitmask.msbb_get! i then
      let e := eval f (l.get! i)
      let mut e_inv := gf_inv (e * e)
      for j in range 0 (2*sys_t) do
        out := out.set! j (out.get! j + e_inv)
        e_inv := e_inv * l.get! i
  pure out

@[extern "lean_bm"]
constant bm
    (s: @&(Vector (2*sys_t) GF))
   : Vector (sys_t+1) GF

constant decrypt
    (images : @&(Vector N GF))
    (s: @&(Vector (2*sys_t) GF))
   : Nat × BitVec N := Id.run do
  let mut w : Nat := 0
  let mut e : BitVec N := BitVec.zero _
  for i in range 0 N do
    if gf_iszero (images.get! i) &&& 1 = 1 then
      e := e.msbb_set! i True
      w := w + 1
  pure (w, e)

def cryptoKemDec (c : @&Ciphertext) (sk : @&SecretKey) : Option Plaintext := do
  let g := sk.goppa
  let l := support_gen sk.controlbits
  let r : BitVec N := c.syndrome ++ BitVec.zero (N-pk_nrows)
  let s := synd g l r
  let locator := bm s
  let images := (λi => gf_inv (eval locator i)) <$> l
  let (w, e) := decrypt images s
  -- Generate preimage
  if w = sys_t ∧ Ciphertext.mkHash e = c.hash ∧ s = synd g l e then
    some $ { e := e, c := c }
  else
    none

end Mceliece348864Ref