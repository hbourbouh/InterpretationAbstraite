(*
 * TINY (Tiny Is Not Yasa (Yet Another Static Analyzer)):
 * a simple abstract interpreter for teaching purpose.
 * Copyright (C) 2012  P. Roux
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *)

module type Domain = sig
  val name : string
  val parse_param : string -> unit
  val fprint_help : Format.formatter -> unit
  val base_type: Ast.base_type
  type t
  val fprint : Format.formatter -> t -> unit
  val order : t -> t -> bool
  val top : t
  val bottom : t
  val is_bottom : t -> bool
  val join : t -> t -> t
  val meet : t -> t -> t
  val widening : t -> t -> t
  val sem_itv : Q.t -> Q.t -> t
  val sem_plus : t -> t -> t
  val sem_minus : t -> t -> t
  val sem_times : t -> t -> t
  val sem_div : t -> t -> t
  val sem_geq0 : t -> t
  (* val backsem_le : t -> t -> t * t *)
  val backsem_plus : t -> t -> t -> t * t
  val backsem_minus : t -> t -> t -> t * t
  val backsem_times : t -> t -> t -> t * t
  val backsem_div : t -> t -> t -> t * t
end

module MakeRelational (D : Domain) : Relational.Domain = struct
  let name = D.name

  let parse_param = D.parse_param

  let fprint_help = D.fprint_help

  let base_type = D.base_type

  type t = EnvBot | Env of D.t Name.Map.t

  let fprint ff t = match t with
    | EnvBot -> Format.fprintf ff "⊥"
    | Env m ->
      if Name.Map.is_empty m then
        Format.fprintf ff "⊤"
      else
        let first = ref true in
        Name.Map.iter
          (fun n v ->
            if !first then begin
              Format.fprintf ff "@[<2>{ %s : %a" n D.fprint v;
              first := false
            end else
              Format.fprintf ff ",@ %s : %a" n D.fprint v)
          m;
        Format.fprintf ff " }@]"

  let find_or_top n m = try Name.Map.find n m with Not_found -> D.top

  let order_print n x y =
    let b = D.order x y in
    Report.nlogf n "%a@ ⊑ %a@ = %b."
      D.fprint x D.fprint y b;
    b

  let order t1 t2 = match t1, t2 with
    | EnvBot, _ -> true
    | _, EnvBot -> false
    | Env m1, Env m2 -> Name.Map.fold
      (fun n v2 b -> b && order_print 5 (find_or_top n m1) v2)
      m2
      true

  let top _ = Env Name.Map.empty
  let bottom _ = EnvBot

  let is_bottom t = match t with EnvBot -> true | Env m -> Name.Map.exists (fun _ v -> D.is_bottom v) m

  let get_vars t = 
    match t with 
    | EnvBot -> Name.Set.empty 
    | Env m -> Name.Map.fold (fun k _ s -> Name.Set.add k s) m Name.Set.empty

  let join_f s f t1 t2 = match t1, t2 with
    | EnvBot, _ -> t2
    | _, EnvBot -> t1
    | Env m1, Env m2 ->
      let m = Name.Map.fold
        (fun n v1 m ->
          let v2 = find_or_top n m2 in
          let v = f v1 v2 in
          Report.nlogf 5 "%a@ %s %a@ = %a."
            D.fprint v1 s D.fprint v2 D.fprint v;
          if order_print 6 D.top v then m
          else Name.Map.add n v m)
        m1
        Name.Map.empty in
      Env m

  let join = join_f "⊔" D.join

  let meet_print x y =
    let r = D.meet x y in
    Report.nlogf 5 "%a@ ⊓ %a@ = %a."
      D.fprint x D.fprint y D.fprint r;
    r

  let meet t1 t2 = match t1, t2 with
    | EnvBot, _ | _, EnvBot -> EnvBot
    | Env m1, Env m2 ->
      try
        let m = Name.Map.fold
          (fun n v1 m ->
            let v2 = find_or_top n m2 in
            let v = meet_print v1 v2 in
            if order_print 6 v D.bottom then raise Exit
            else Name.Map.add n v m)
          m1
          m2 in
        Env m
      with Exit -> EnvBot

  (* We assume that the analyzed program has a finite number of variables.
   * Then, widening of environments is just a pointwise application of
   * D.widening.*)
  let widening = join_f "∇" D.widening

  let rec eval_expr env e = match e.Ast.expr_desc with
    | Ast.Cst (n,ns) -> eval_expr env (Ast.mk_expr e.Ast.expr_loc e.Ast.expr_type (Ast.Rand ((n,ns), (n,ns))))
    | Ast.Var n -> find_or_top n env
    | Ast.Binop (bop, e1, e2) ->
      let v1 = eval_expr env e1 in
      let v2 = eval_expr env e2 in
      let s, sem = match bop with
        | Ast.Plus -> "sem_plus", D.sem_plus
        | Ast.Minus -> "sem_minus", D.sem_minus
        | Ast.Times -> "sem_times", D.sem_times
        | Ast.Div -> "sem_div", D.sem_div in
      let v = sem v1 v2 in
      Report.nlogf 5 "%s@ %a@ %a@ = %a."
        s D.fprint v1 D.fprint v2 D.fprint v;
      v
    | Ast.Rand ((n1, _), (n2, _)) ->
      let v = D.sem_itv n1 n2 in
      Report.nlogf 5 "sem_itv@ %a@ %a@ = %a." Q.pp_print n1 Q.pp_print n2 D.fprint v;
      v
    | Ast.Call (f, args) -> (* TODO *) D.top
    | Ast.Cond _ -> (* TODO guard e env *) D.top 

  let assignment n e t = 
    if e.Ast.expr_type = D.base_type then (
      match t with
      | EnvBot -> EnvBot
      | Env m ->
	let t = eval_expr m e in
	if order_print 6 t D.bottom then EnvBot
	else if order_print 6 D.top t then Env (Name.Map.remove n m)
	else Env (Name.Map.add n t m)
    )
    else
      t
	    
  let rec backeval_expr env e t = match e.Ast.expr_desc with
    | Ast.Cst (b,bs) -> backeval_expr env (Ast.mk_expr e.Ast.expr_loc e.Ast.expr_type (Ast.Rand ((b,bs), (b,bs)))) t
    | Ast.Var n ->
      let t' = find_or_top n env in
      let t = meet_print t t' in
      if order_print 6 t D.bottom then raise Exit
      else if order_print 6 D.top t then env
      else Name.Map.add n t env
    | Ast.Binop (bop, e1, e2) ->
      (* not very efficient,
       * but guards should not be very large anyway *)
      let t1 = eval_expr env e1 in
      let t2 = eval_expr env e2 in
      let s, backsem = match bop with
        | Ast.Plus -> "backsem_plus", D.backsem_plus
        | Ast.Minus -> "backsem_minus", D.backsem_minus
        | Ast.Times -> "backsem_times", D.backsem_times
        | Ast.Div -> "backsem_div", D.backsem_div in
      let t1', t2' = backsem t1 t2 t in
      Report.nlogf 5 "%s@ %a@ %a@ %a@ = @[%a,@ %a@]."
        s D.fprint t1 D.fprint t2 D.fprint t D.fprint t1' D.fprint t2';
      backeval_expr (backeval_expr env e1 t1') e2 t2'
    | Ast.Rand _ ->
      let t' = eval_expr env e in
      let t = meet_print t t' in
      if order_print 6 t D.bottom then raise Exit
      else env
    | Ast.Call (f, args) -> (* TODO *) env
    | Ast.Cond _ -> (* TODO guard e env *) env


  let guard e t = 
    match e.Ast.expr_desc with
    | Ast.Cond (e,sl) -> (
      if e.Ast.expr_type = D.base_type then (
	match t with
	| EnvBot -> EnvBot
	| Env m -> 
	  let pre_expr, post_val = 
	    (match base_type, sl with
	    | Ast.IntT, Ast.Strict -> (* e > 0, ie. e >= 1, ie. e-1 >= 0 *) 
	      let minus_one = Ast.mk_cst_expr e.Ast.expr_loc e.Ast.expr_type (Q.minus_one, "-1") in
	      let f op e = Ast.mk_expr e.Ast.expr_loc Ast.IntT (Ast.Binop (op, e, minus_one)) in
	      (f Ast.Plus), (fun x -> D.sem_plus x (D.sem_itv Q.one Q.one))
	    | Ast.IntT, Ast.Loose (* e >= 0 *)
	    | Ast.RealT, _ -> (fun id -> id), (fun id -> id)
	    | _ -> assert false)
	  in
	  
	  let t = eval_expr m (pre_expr e) in
	  let t' = post_val (D.sem_geq0 t) in
	  Report.nlogf 5 "sem_guard %a%s0 = %a." D.fprint (eval_expr m e) (Ast.string_of_cmp sl) D.fprint t';
	  try Env (backeval_expr m e t')
	  with Exit -> EnvBot
      )
      else
	t
    )
    | _ -> assert false

		      (* let guard_real e1 e2 t = match t with *)
		      (*   | EnvBot -> EnvBot *)
		      (*   | Env m -> *)
		      (*     let t1, t2 = eval_expr m e1, eval_expr m e2 in *)
		      (*     let t1', t2' = D.backsem_le t1 t2 in *)
		      (*     Report.nlogf 5 "backsem_le@ %a@ %a@ = @[%a,@ %a@]." *)
		      (*       D.fprint t1 D.fprint t2 D.fprint t1' D.fprint t2'; *)
		      (*     try *)
		      (*       let t1'' = Env (backeval_expr m e1 t1') in *)
		      (*       let t2'' = Env (backeval_expr m e2 t2') in *)
		      (*       meet t1'' t2'' *)
		      (*     with Exit -> EnvBot *)
		      end
