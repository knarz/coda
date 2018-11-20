open Core_kernel
open Snark_bits
open Fold_lib
open Tuple_lib

module type S = sig
  type curve
  type curve_vector

  module Digest : sig
    type t [@@deriving bin_io, sexp, eq, hash, compare]

    val size_in_bits : int

    val fold : t -> bool Triple.t Fold.t

    val ( = ) : t -> t -> bool

    module Bits : Bits_intf.S with type t := t

    module Snarkable (Impl : Snark_intf.S) :
      Impl.Snarkable.Bits.Lossy
      with type Packed.var = Impl.Field.Checked.t
       and type Packed.value = Impl.Field.t
       and type Unpacked.value = Impl.Field.t
  end

  module Params : sig
    type t = curve_vector
  end

  module State : sig
    type t = {triples_consumed: int; acc: curve; params: Params.t}

    val create : ?triples_consumed:int -> ?init:curve -> Params.t -> t

    val update_fold : t -> bool Triple.t Fold.t -> t

    val digest : t -> Digest.t

    val salt : Params.t -> string -> t
  end

  val hash_fold : State.t -> bool Triple.t Fold.t -> State.t

  val digest_fold : State.t -> bool Triple.t Fold.t -> Digest.t
end

module Make (Field : sig
  type t [@@deriving sexp, bin_io, compare, hash, eq]

  include Snarky.Field_intf.S with type t := t
end)
(Bigint : Snarky.Bigint_intf.Extended with type field := Field.t) (Curve : sig
    type t

    val to_coords : t -> Field.t * Field.t

    val zero : t

    val add : t -> t -> t

    val negate : t -> t

    val dup : t -> t

    val unsafe_add_in_place : dst:t -> t -> t

    module Vector : Snarky.Vector.S with type elt := t

    val pedersen_inner : params:Vector.t -> i:int -> b0:bool -> b1:bool -> b2:bool -> acc:t -> unit
end) : S with type curve := Curve.t and type Digest.t = Field.t and type curve_vector := Curve.Vector.t = struct
  module Digest = struct
    type t = Field.t [@@deriving sexp, bin_io, compare, hash, eq]

    let size_in_bits = Field.size_in_bits

    let ( = ) = equal

    module Snarkable = Bits.Snarkable.Field
    module Bits = Bits.Make_field (Field) (Bigint)

    let fold t = Fold.group3 ~default:false (Bits.fold t)
  end

  module Params = struct
    type t = Curve.Vector.t

    let of_array l =
      let vec = Curve.Vector.create () in
      Array.iter l ~f:(fun (e1, e2, e3, e4) ->
      Curve.Vector.emplace_back vec e1 ;
      Curve.Vector.emplace_back vec e2 ;
      Curve.Vector.emplace_back vec e3 ;
      Curve.Vector.emplace_back vec e4 ) ;
      vec
  end

  module State = struct
    type t = {triples_consumed: int; acc: Curve.t; params: Params.t}

    let create ?(triples_consumed = 0) ?(init = Curve.zero) params =
      {acc= Curve.dup init; triples_consumed; params}

    let update_fold (t : t) (fold : bool Triple.t Fold.t) =
      let params = t.params in
      let acc, triples_consumed =
        fold.fold ~init:(t.acc, t.triples_consumed) ~f:(fun (acc, i) (b0, b1, b2) ->
            let () =
              Curve.pedersen_inner ~params ~i ~b0 ~b1 ~b2 ~acc
            in
            (acc, i + 1) )
      in
      {t with acc; triples_consumed}

    let digest t =
      let x, _y = Curve.to_coords t.acc in
      x

    let salt params s = update_fold (create params) (Fold.string_triples s)
  end

  let hash_fold s fold = State.update_fold s fold

  let digest_fold s fold = State.digest (hash_fold s fold)
end
