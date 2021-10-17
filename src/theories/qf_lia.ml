(**
  {1 Lia}
  The Modulus internal solver for LIA

  Disclaimer : this module is a "work in progress"
*)

open Logic
open Model

module Interval2 = struct
  type t =
    | Top
    | Bot
    | OpenL of int
    | OpenR of int
    | Intv of int * int

  let singleton v = Intv (v, v)

  let to_string = function
    | Top -> "⊤"
    | Bot -> "⊥"
    | OpenL v -> Printf.sprintf "]-∞; %d]" v
    | OpenR v -> Printf.sprintf "[%d; +∞[" v
    | Intv (lo, hi) -> Printf.sprintf "[%d; %d]" lo hi

  let pp_print fmt x = Format.fprintf fmt "%s" (to_string x)

  let normalize = function
    | Intv (lo, hi) as i -> if lo > hi then Bot else i
    | _ as i -> i

  let add x y =
    let r =
      match x, y with
      | Bot, _ | _, Bot -> Bot
      | Top, _ | _, Top -> Top
      | OpenL v, OpenL v' -> OpenL (v + v')
      | OpenR v, OpenR v' -> OpenR (v + v')
      | OpenL _, OpenR _ | OpenR _, OpenL _ -> Top
      | Intv (_, hi), OpenL v | OpenL v, Intv (_, hi) -> OpenL (hi + v)
      | Intv (lo, _), OpenR v | OpenR v, Intv (lo, _) -> OpenR (lo + v)
      | Intv (lo, hi), Intv (lo', hi') -> Intv (lo + lo', hi + hi')
    in normalize r

  let inter x y =
    let r =
      match x, y with
      | Bot, _ | _, Bot -> Bot
      | Top, x | x, Top -> x
      | OpenL v, OpenL v' -> OpenL (min v v')
      | OpenR v, OpenR v' -> OpenR (max v v')
      | OpenL v, OpenR v' | OpenR v', OpenL v -> Intv (min v v', max v v')
      | Intv (lo, hi), Intv (lo', hi') -> Intv (max lo lo', min hi hi')
      | OpenL v, Intv (lo, _) | Intv (lo, _), OpenL v -> OpenL (min v lo)
      | OpenR v, Intv (_, hi) | Intv (_, hi), OpenR v -> OpenR (max v hi)
    in normalize r

  let is_empty i = (i = Bot)

  let neg = function
    | Bot -> Bot
    | Top -> Top
    | OpenL v -> OpenR (-v)
    | OpenR v -> OpenL (-v)
    | Intv (lo, hi) -> Intv (-hi, -lo)
  
  let sub x y = add x (neg y)

  let add_inv x y r = (sub r y, sub r x)

  let _mid x y =
    let m = x / 2 + y / 2 in
    (m, m + (x land 1) * (y land 1))

  let split = function
    | Top -> `Split (OpenL 0, OpenR 0)
    | Bot -> failwith "cannot split ⊥"
    | Intv (lo, hi) ->
      if lo = hi then `Single lo else
      let (m, m') = _mid lo hi in
      `Split (Intv (lo, m), Intv (m', hi))
    | OpenL v ->
      `Split (OpenL (v - 1), Intv (v, v))
    | OpenR v ->
      `Split (Intv (v, v), OpenR (v + 1))

  let peek = function
      | Top -> 0
      | Bot -> failwith "cannot peek a value in ⊥"
      | Intv (lo, _) -> lo
      | OpenL v | OpenR v -> v
end

module Solver = struct
  type state = (term * Interval2.t) list

  type 'a status =
    | Value of 'a
    | Update of state * 'a
    | Fail of string
    | Abort

  type 'a update = state -> 'a status

  let return (x : 'a) : 'a update = fun _ -> Value x

  let update t x : 'a update = fun s ->
    let open Interval2 in
    match List.assoc_opt t s with
    | Some x' ->
      if x = x' then Value x'
      else
        let d = inter x x' in
        if is_empty d then
          Fail (Printf.sprintf "update failed %s ∩ %s = %s"
            (to_string x) (to_string x') (to_string d))
        else Update ((t, d)::List.remove_assoc t s, d)
    | None ->
      Update ((t, x)::s, x)

  exception Contradiction of string
  exception Aborted

  let get (s : 'a status) : 'a =
    match s with
    | Abort -> raise Aborted
    | Fail l -> raise (Contradiction ("nothing to get because: " ^ l))
    | Value v -> v
    | Update (_, v) -> v

  let (let*) (m : 'a update) (f : 'a -> 'b update) : 'b update = fun s ->
    match m s with
    | Abort -> Abort
    | Fail _ as err -> err
    | Value v -> f v s
    | Update (e, v) ->
      match f v e with
      | Value v -> Update (e, v)
      | _ as ret -> ret

  let rec eval (x : term) : Interval2.t update = fun s ->
    match List.assoc_opt x s with
    | Some v -> Value v
    | None ->
      match x with
      | Var _ -> update x Interval2.Top s
      | Cst v -> update x (Interval2.singleton v) s
      | Add (t1, t2) ->
        begin
          let* v1 = eval t1 in
          let* v2 = eval t2 in
          update x (Interval2.add v1 v2)
        end s

  let (>>) (u1 : 'a update) (u2 : 'b update) : 'b update =
    let* _ = u1 in u2

  let leak : state update = fun s -> Value s

  let print_state =
    let open Interval2 in
    List.iter (fun (x, d) ->
      match x with
      | Var x ->
        Format.printf "%s := %a\n" x pp_print d
      | _ -> ()
    )

  let fail msg = fun _ -> Fail msg

  let propagate_one (Eq (t1, t2) : atom) : unit update =
    let* d1 = eval t1 in
    let* d2 = eval t2 in
    let d = Interval2.inter d1 d2 in
    update t1 d >> update t2 d >> return ()

  let propagate_one_backward (Eq (t1, t2) : atom) : unit update =
    let rec step (t : term) (dt : Interval2.t) : unit update =
      match t with
      | Cst _ | Var _ -> update t dt >> return ()
      | Add (t1, t2) ->
        let* d1 = eval t1 in
        let* d2 = eval t2 in
        let (d1', d2') = Interval2.add_inv d1 d2 dt in
        step t1 d1' >> step t2 d2' >> return ()
    in
    let* d1 = eval t1 in
    let* d2 = eval t2 in
    step t1 d1 >> step t2 d2

  let sequence (l : 'a list) (p : 'a -> unit update) : unit update =
    List.fold_left (>>) (return ()) (List.map p l)

  let propagate l : unit update =
    sequence l propagate_one
    >> sequence l propagate_one_backward

  let (<|>) (u1 : 'a update) (u2 : 'b update) : 'b update = fun s ->
    match u1 s with
    | Fail _ ->
      (* Printf.printf "fallback...\n"; *)
      u2 s
    | _ as r -> r

  let rec zseq x =
    Lstream.Cons (x, lazy (zseq (x + 1)))
  and zseq' x =
    Lstream.Cons (x, lazy (zseq' (x - 1)))

  let extract_model (p : atom list) =
    let vars =
        List.map avars p
        |> List.fold_left VSet.union VSet.empty
        |> VSet.to_seq
        |> List.of_seq
    in
    let rec step vlist (model : Model.t) : Model.t update =
      match vlist with
      | [] ->
        if List.for_all (fun a -> Option.get (check_atom a model)) p
        then return model
        else fail "extract model"
      | x::xs ->
        let open Interval2 in
        let* dx = eval (Var x) in
        let decide x v = update (Var x) (singleton v) >> propagate p in
        match Interval2.split dx with
        | `Split (d1, d2) ->
          let c1, c2 = peek d1, peek d2 in
          (decide x c1 >> (step xs ((x, c1)::model)))
          <|>
          (decide x c2 >> (step xs ((x, c2)::model)))
          <|>
          (update (Var x) d1 >> propagate p >> step vlist model)
          <|>
          (update (Var x) d2 >> propagate p >> step vlist model)
        | `Single v ->
          step xs ((x, v)::model)
      in
      step vars []
  
  let solve (p : atom list) =
    let go = propagate p >> extract_model p in
    get (go [])
end

let lia (l : atom list) : answer =
  try SAT (Solver.solve l)
  with
  | Solver.Contradiction _msg ->
    (* Printf.printf "unsat because : %s\n" _msg; *)
    UNSAT
  | _ -> UNKNOWN



