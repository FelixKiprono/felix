(* New monomorphisation routine *)
open Flx_util
open Flx_btype
open Map
open Flx_mtypes2
open Flx_print
open Flx_types
open Flx_bbdcl
open Flx_bexpr
open Flx_bexe
open Flx_bparameter
module CS = Flx_code_spec

(* NOTES
   We make monomorphic specialisations of everything used.
   For Felix entities, references lose their type arguments (ts) and the
   entity loses its type paramaters (vs).

   For C things, we monomorphise the visible code, and so get
   a copy of the C thing, however the C thing doesn't lose
   its type parameters (vs) and references don't lose the
   type arguments (ts) .. even though the copy is monomorphic.

   This is because this routine does not substitute type arguments
   into the C code fragments, so the C code part of the entity
   remains polymorphic, even though the Felix part of the interface
   is monomorphised.

*)


let show bsym_table i = 
  try 
    Flx_bsym_table.find_id bsym_table i ^ "<" ^ si i ^ ">"
   with Not_found -> "index_" ^ si i

let showts bsym_table i ts =
  show bsym_table i ^ "[" ^ catmap "," (sbt bsym_table) ts ^ "]"

let showvars bsym_table vars = 
  catmap "," (fun (i,t)-> si i ^ " |-> " ^ sbt bsym_table t) vars

(* ----------------------------------------------------------- *)
(* ROUTINES FOR REPLACING TYPE VARIABLES IN TYPES              *)
(* ----------------------------------------------------------- *)

let check_mono bsym_table t =
  if Flx_unify.var_occurs bsym_table t then begin
    print_endline (" **** Failed to monomorphise type " ^ sbt bsym_table t);
    print_endline (" **** got type " ^ sbt bsym_table t);
    assert false
  end
  ;
  match t with
  | BTYP_none 
  | BTYP_type_apply _
  | BTYP_type_function _
  | BTYP_type_tuple _
  | BTYP_type_match _
  | BTYP_type_set _
  | BTYP_type_set_union _
  | BTYP_type_set_intersection _
    -> 
    (* print_endline ("[flx_numono:check_mono]: Unexpected type expression" ^ sbt bsym_table t); *)
     ()
  | _ -> ()

  
let check_mono_vars bsym_table vars t =
  try check_mono bsym_table t
  with _ -> 
    print_endline (" **** using varmap " ^ showvars bsym_table vars);
    assert false

let mono_type syms bsym_table vars t = 
(*
print_endline (" ** begin mono_type " ^ sbt bsym_table t);
*)
  let t = Flx_unify.list_subst syms.counter vars t in
  let t = Flx_beta.beta_reduce "mono_type"
    syms.Flx_mtypes2.counter
    bsym_table
    Flx_srcref.dummy_sr
    t
  in 
  let t = Flx_unify.normalise_tuple_cons bsym_table t in
  begin try check_mono bsym_table t with _ -> assert false end;
(*
print_endline (" ** end Mono_type " ^ sbt bsym_table t);
*)
  t

let rec mono_expr syms bsym_table vars e =
(*
print_endline (" ** begin mono_expr " ^ sbe bsym_table e);
*)
  let f_btype t = mono_type syms bsym_table vars t in
  let f_bexpr e = mono_expr syms bsym_table vars e in
  let e = Flx_bexpr.map ~f_btype ~f_bexpr e in
(*
print_endline (" ** end mono_expr " ^ sbe bsym_table e);
*)
  e

let rec mono_exe syms bsym_table vars exe =
(*
print_endline (" ** begin mono_exe " ^ string_of_bexe bsym_table 0 exe);
*)
  let f_btype t = mono_type syms bsym_table vars t in
  let f_bexpr e = mono_expr syms bsym_table vars e in
  let exe = Flx_bexe.map ~f_btype ~f_bexpr exe in
(*
print_endline (" ** end mono_exe " ^ string_of_bexe bsym_table 0 exe);
*)
  exe

(* ----------------------------------------------------------- *)
(* ROUTINES FOR REPLACING REFS TO VIRTUALS WITH INSTANCES      *)
(* ----------------------------------------------------------- *)

let flat_typeclass_fixup_type syms bsym_table polyinst t =
  match t with
  | BTYP_inst (i,ts) ->
    let i',ts' = polyinst i ts in
    let t = btyp_inst (i',ts') in
    t
  | x -> x

let rec typeclass_fixup_type syms bsym_table polyinst t =
  let f_btype t = typeclass_fixup_type syms bsym_table polyinst t in
  let t = Flx_btype.map ~f_btype t in
  let t = flat_typeclass_fixup_type syms bsym_table polyinst t in
  t

let flat_typeclass_fixup_expr syms bsym_table polyinst (e,t) =
  let x = match e with
  | BEXPR_apply_prim (i',ts,a) -> assert false
  | BEXPR_apply_direct (i,ts,a) -> assert false
  | BEXPR_apply_struct (i,ts,a) -> assert false
  | BEXPR_apply_stack (i,ts,a) -> assert false
  | BEXPR_ref (i,ts)  ->
    let i,ts = polyinst i ts in
    bexpr_ref t (i,ts)

  | BEXPR_varname (i',ts') ->
    let i,ts = polyinst i' ts' in
    bexpr_varname t (i,ts)

  | BEXPR_closure (i,ts) ->
    let i,ts = polyinst i ts in
    bexpr_closure t (i,ts)

  | x -> x, t
  in
  x

let rec typeclass_fixup_expr syms bsym_table polyinst e =
  let f_bexpr e = typeclass_fixup_expr  syms bsym_table polyinst e in
  let e = flat_typeclass_fixup_expr syms bsym_table polyinst e in
  let e = Flx_bexpr.map ~f_bexpr e in
  e 

(* mt is only used to fixup svc and init hacks *)
let flat_typeclass_fixup_exe syms bsym_table polyinst mt exe =
(*
  print_endline ("TYPECLASS FIXUP EXE[In] =" ^ string_of_bexe bsym_table 0 exe);
*)
  let result =
  match exe with
  | BEXE_call_direct (sr, i,ts,a) -> assert false
  | BEXE_jump_direct (sr, i,ts,a) -> assert false
  | BEXE_call_prim (sr, i',ts,a) -> assert false
  | BEXE_call_stack (sr, i,ts,a) -> assert false

  | x -> x
  in
  (*
  print_endline ("FIXUP EXE[Out]=" ^ string_of_bexe sym_table 0 result);
  *)
  result

(* ----------------------------------------------------------- *)
(* ROUTINES FOR REPLACING REFS TO POLYMORPHS WITH MONOS        *)
(* ----------------------------------------------------------- *)

let flat_poly_fixup_type syms bsym_table polyinst t =
(*
  if not (complete_type t) then
    print_endline ("flat_poly_fixup_type: type isn't complete " ^ sbt bsym_table t);
*)

  match t with
  | BTYP_inst (i,ts) ->
    let i',ts' = polyinst i ts in
    let t' = btyp_inst (i',ts') in
(*
print_endline ("poly_fixup_type: " ^ showts bsym_table i ts ^ " --> " ^ showts bsym_table i' ts');
*)
    t'
  | x -> x

(* this has to be top down, so instances i,ts use the original
ts, then the ts get analysed. Otherwise, we'd get new symbols
in the ts and there's be no match on the replacement table
*)

let rec rec_poly_fixup_type syms bsym_table polyinst t =
  let t = flat_poly_fixup_type syms bsym_table polyinst t in
  let f_btype t = rec_poly_fixup_type syms bsym_table polyinst t in
  let t = Flx_btype.map ~f_btype t in
  t

let poly_fixup_type syms bsym_table polyinst t =
 let t' = rec_poly_fixup_type syms bsym_table polyinst t in
(*
 print_endline ("POLY FIXUP TYPE: " ^ sbt bsym_table t ^ " --> " ^ sbt bsym_table t');
*)
 t'

let flat_poly_fixup_expr syms bsym_table polyinst (e,t) =
  let x = match e with
  | BEXPR_apply_prim (i',ts,a) -> assert false
  | BEXPR_apply_direct (i,ts,a) -> assert false
  | BEXPR_apply_struct (i,ts,a) -> assert false
  | BEXPR_apply_stack (i,ts,a) -> assert false
  | BEXPR_ref (i,ts)  ->
    let i,ts = polyinst i ts in
    bexpr_ref t (i,ts)

  | BEXPR_varname (i',ts') ->
    let i,ts = polyinst i' ts' in
    bexpr_varname t (i,ts)

  | BEXPR_closure (i,ts) ->
    let i,ts = polyinst i ts in
    bexpr_closure t (i,ts)

  | x -> x, t
  in
  x

let rec poly_fixup_expr syms bsym_table polyinst e =
  let f_bexpr e = poly_fixup_expr  syms bsym_table polyinst e in
  let f_btype t = poly_fixup_type syms bsym_table polyinst t in
  let e = flat_poly_fixup_expr syms bsym_table polyinst e in
  let e = Flx_bexpr.map ~f_bexpr ~f_btype e in
  e 

(* mt is only used to fixup svc and init hacks *)
let flat_poly_fixup_exe syms bsym_table polyinst parent_ts mt exe =
(*
  print_endline ("TYPECLASS FIXUP EXE[In] =" ^ string_of_bexe bsym_table 0 exe);
*)
  let result =
  match exe with
  | BEXE_call_direct (sr, i,ts,a) -> assert false
  | BEXE_jump_direct (sr, i,ts,a) -> assert false
  | BEXE_call_prim (sr, i',ts,a) -> assert false
  | BEXE_call_stack (sr, i,ts,a) -> assert false

  (* this is deviant case: implied ts is vs of parent! *)
  | BEXE_init (sr,i,e) ->
(*
    print_endline ("[flat_poly_fixup_exe: init] Deviant case variable " ^ si i);
*)
    let vs = 
      try Flx_bsym_table.find_bvs bsym_table i 
      with Not_found -> assert false
    in
    assert (List.length vs = List.length parent_ts);
    let j,ts = polyinst i parent_ts in
(*
    if i <> j then 
      print_endline ("[init] Remapped deviant variable to " ^ si j);
*)
    bexe_init (sr,j,e)

  | BEXE_svc (sr,i) ->
    (*
    print_endline ("[flat_poly_fixup_exe: svc] Deviant case variable " ^ si i);
    *)
    let vs = 
      try Flx_bsym_table.find_bvs bsym_table i 
      with Not_found -> assert false
    in
    assert (List.length vs = List.length parent_ts);
    let j,ts = polyinst i parent_ts in
    (*
      if i <> j then
        print_endline ("[svc] Remapped deviant variable to " ^ si i);
     *)
    bexe_svc (sr,j)

  | x -> x
  in
  (*
  print_endline ("FIXUP EXE[Out]=" ^ string_of_bexe sym_table 0 result);
  *)
  result

(* ----------------------------------------------------------- *)
(* COMPLETE PROCESSING ROUTINES                                *)
(* ----------------------------------------------------------- *)

let fixup_type syms bsym_table vars bsym virtualinst polyinst t =
(*
  print_endline ("    ** mono_type " ^ sbt bsym_table t);
*)
  let t = mono_type syms bsym_table vars t in
(*
  print_endline ("    ** typeclass_fixup_type " ^ sbt bsym_table t);
*)
  let t = typeclass_fixup_type syms bsym_table virtualinst  t in
(*
  print_endline ("    ** Betareduce " ^ sbt bsym_table t);
*)
  let t = Flx_beta.beta_reduce "flx_mono: mono, metatype"
    syms.Flx_mtypes2.counter
    bsym_table
    (Flx_bsym.sr bsym)
    t
  in 
(*
  print_endline ("    ** poly_fixup_type " ^ sbt bsym_table t);
*)
  let t = poly_fixup_type syms bsym_table polyinst t in
(*
  print_endline ("    ** Polyfixedup" ^ sbt bsym_table t );
*)
  t

let fixup_req syms bsym_table vars polyinst (i,ts) : Flx_types.bid_t * Flx_btype.t list =
  let ts = List.map (mono_type syms bsym_table vars) ts in
  let j,ts = polyinst i ts in
  let ts = List.map (poly_fixup_type syms bsym_table polyinst) ts in
  j,ts

let fixup_reqs syms bsym_table vars polyinst reqs : Flx_bbdcl.breqs_t = 
  List.map (fixup_req syms bsym_table vars polyinst) reqs

let fixup_expr syms bsym_table monotype virtualinst polyinst e =
  print_endline ("[fixup_expr] input               : " ^ sbe bsym_table e);
  (* monomorphise the code by eliminating type variables *)
  let e = Flx_bexpr.map ~f_btype:monotype e in
(*
  print_endline ("[fixup_expr] monomorphised       : " ^ sbe bsym_table e);
*)
  (* eliminate virtual calls by mapping to instances *)
  let e = typeclass_fixup_expr syms bsym_table virtualinst e in
(*
  print_endline ("[fixup_expr] virtuals eliminated : " ^ sbe bsym_table e);
*)
  (* replace applications of polymorphic function (or variable)
    with applications of new monomorphic ones
  *)
  let e = poly_fixup_expr syms bsym_table polyinst e in
(*
  print_endline ("[fixup_expr] polysyms eliminated : " ^ sbe bsym_table e);
*)
  e

let show_exe bsym_table exe = string_of_bexe bsym_table 4 exe
let show_exes bsym_table exes = catmap "\n" (show_exe bsym_table) exes


(* completely process a list of exes *)
(* rewrite to do in one pass *)
let fixup_exes syms bsym_table vars virtualinst polyinst parent_ts exes =
 let mt t = mono_type syms bsym_table vars t in

 (* monomorphise the code by eliminating type variables *)
(*
  print_endline ("To fixup exes:\n" ^ show_exes bsym_table exes);
*)
  let rexes = List.fold_left 
    (fun oexes iexe -> 
      match iexe with
      | BEXE_call (sr,(BEXPR_closure (f,[]),_),_) ->
        begin match Flx_bsym_table.find_bbdcl bsym_table f with
        (* elide calls to empty non-virtual procedures 
           Inlining does this anyhow, but this cleans up the
           diagnostic prints and reduces the crap in the symbol
           table a little earlier.
        *) 
        | BBDCL_fun (props,_,_,_,[]) when not (List.mem `Virtual props) -> oexes 
        | _ -> mono_exe syms bsym_table vars iexe :: oexes
        end 
      | _ ->  mono_exe syms bsym_table vars iexe :: oexes
    ) 
    [] 
    exes 
  in
(*
  print_endline ("Monomorphised:\n" ^ show_exes bsym_table (List.rev rexes));
*)
(*
  print_endline ("VARS=" ^ showvars bsym_table vars);
*)
  (* eliminate virtual calls by mapping to instances *)
  (* order doesn't matter here *)
  let exes = List.rev_map (fun exe -> Flx_bexe.map ~f_bexpr:(typeclass_fixup_expr syms bsym_table virtualinst) exe) rexes in
  let rexes = List.rev_map (fun exe -> flat_typeclass_fixup_exe syms bsym_table virtualinst mt exe) exes in
(*
  print_endline ("Virtuals Instantiated:\n" ^ show_exes bsym_table (List.rev exes));
*)
  let exes = List.rev_map (flat_poly_fixup_exe syms bsym_table polyinst parent_ts mt)  rexes in
(*
  print_endline ("Special calls monomorphised:\n" ^ show_exes bsym_table exes);
*)
  (* replace applications of polymorphic function (or variable)
    with applications of new monomorphic ones
  *)
  let exes = List.map (fun exe -> Flx_bexe.map ~f_bexpr:(poly_fixup_expr syms bsym_table polyinst) exe) exes in
(*
  print_endline ("Applies polyinst:\n" ^ show_exes bsym_table exes);
*)
  exes

let fixup_qual vars mt qual = 
  match qual with
  | `Bound_needs_shape t -> `Bound_needs_shape (mt vars t)
  | x -> x
 

let monomap_compare (i,ts) (i',ts') = 
  let counter = ref 1 in (* HACK *)
  let dummy = Flx_bsym_table.create () in 
  if i = i' && List.fold_left2 (fun r t t' -> r && Flx_unify.type_eq dummy counter t t') true ts ts'
  then 0 else compare (i,ts) (i',ts') 

module MonoMap = Map.Make (
  struct 
    type t = int * Flx_btype.t list 
    let compare = monomap_compare 
  end
)

let find_felix_inst syms bsym_table processed to_process nubids i ts : int =
  let find_inst syms processed to_process i ts =
    try 
      Some (MonoMap.find (i,ts) !processed)
    with Not_found ->
    try
      Some (MonoMap.find (i,ts) !to_process)
    with Not_found -> None
  in
  match find_inst syms processed to_process i ts with
  | None ->
    let k = 
      if List.length ts = 0 then i else  
       let nubid = fresh_bid syms.counter  in
       nubids := BidSet.add nubid (!nubids);
       nubid
    in
    let target = k in
    to_process := MonoMap.add (i,ts) target !to_process;
    (*
    if i <> k then
      print_endline ("Add inst to process: " ^ showts bsym_table i ts ^ " --> "^si k);
    *)
    k
  | Some (k) -> k

let mono_bbdcl syms bsym_table processed to_process nubids virtualinst polyinst ts bsym =
(*
  print_endline ("[mono_bbdcl] " ^ Flx_bsym.id bsym);
  print_endline ("ts=[" ^ catmap "," (sbt bsym_table) ts ^ "]");
  List.iter (fun t -> if not (complete_type t) then 
    print_endline ("Argument not complete!!!!!!!!!!!!!!!!!!!!!!!")
  )
  ts;
*)
  begin try List.iter (check_mono bsym_table) ts with _ -> assert false end;

  let mt vars t = fixup_type syms bsym_table vars bsym virtualinst polyinst t in
  let bbdcl = Flx_bsym.bbdcl bsym in
  match bbdcl with
  | BBDCL_fun (props,vs,(ps,traint),ret,exes) ->
    begin try
      let props = List.filter (fun p -> p <> `Virtual) props in
      if List.length vs <> List.length ts then begin try
        print_endline ("[mono] vs/ts mismatch in " ^ Flx_bsym.id bsym ^ " vs=[" ^ 
          catmap "," (fun (s,i) -> s) vs ^ "]");
        print_endline ("ts=[" ^ catmap "," (sbt bsym_table) ts ^ "]");
        assert false
        with Not_found -> print_endline "Not_found printint ts?"; assert false
      end;
      let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
      let ret = 
        try mt vars ret 
        with Not_found -> print_endline "Not_found fixing up return type"; 
          print_endline ("Ret=" ^ sbt bsym_table ret); 
          assert false 
      in
      let ps = try
        (*
        print_endline ("+++processing parameters of " ^ Flx_bsym.id bsym);
        *)
        let ps = List.map (fun {pkind=pk; pid=s;pindex=i; ptyp=t} ->
        {pkind=pk;pid=s;pindex=fst (polyinst i ts);ptyp=mt vars t}) ps in
        (*
        print_endline ("+++parameters processed: " ^ Flx_bsym.id bsym);
        *)
        ps
        with Not_found -> print_endline ("Not Found FIXING parameters"); assert false
      in
      let traint =
        match traint with
        | None -> None
        | Some x -> Some (fixup_expr syms bsym_table (mt vars) virtualinst polyinst x)
      in
      let exes = 
        try fixup_exes syms bsym_table vars virtualinst polyinst ts exes 
        with Not_found -> assert false
      in
      let props = List.filter (fun p -> p <> `Virtual) props in
      Some (bbdcl_fun (props,[],(ps,traint),ret,exes))
    with Not_found ->
      assert false
    end

  | BBDCL_val (vs,t,kind) ->
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let t = mt vars t in
    Some (bbdcl_val ([],t,kind))

  (* we have tp replace types in interfaces like Vector[int]
    with monomorphic versions if any .. even if we don't
    monomorphise the bbdcl itself.

    This is weak .. it's redone for each instance, relies
    on mt being idempotent..
  *)
  | BBDCL_external_fun (props,vs,argtypes,ret,reqs,prec, fkind) ->
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let argtypes = List.map (mt vars) argtypes in
    let ret = mt vars ret in
    let reqs = fixup_reqs syms bsym_table vars polyinst reqs in
    let props = List.filter (fun p -> p <> `Virtual) props in
    Some (bbdcl_external_fun (props,vs,argtypes,ret,reqs,prec,fkind))

  | BBDCL_external_const (props, vs, t, CS.Str "#this", reqs) ->
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let _ = mt vars t in
    let reqs = fixup_reqs syms bsym_table vars polyinst reqs in
    Some (bbdcl_external_const (props, [], t, CS.Str "#this", reqs))

  | BBDCL_external_const (props, vs, t,cs, reqs) ->
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let t = mt vars t in
    let reqs = fixup_reqs syms bsym_table vars polyinst reqs in
    Some (bbdcl_external_const (props,vs, t, cs, reqs))
 
  | BBDCL_external_type (vs,quals,cs,reqs)  -> 
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let reqs = fixup_reqs syms bsym_table vars polyinst reqs in
    let quals = List.map (fixup_qual vars mt) quals in
    Some (bbdcl_external_type (vs,quals,cs, reqs))

  | BBDCL_external_code (vs,cs,ikind,reqs)   -> 
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let reqs = fixup_reqs syms bsym_table vars polyinst reqs in
    Some (bbdcl_external_code (vs,cs,ikind,reqs))

  | BBDCL_union (vs,cps) -> 
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let cps = List.map (fun (name,index,argt) -> name,index, mt vars argt) cps in
    Some (bbdcl_union ([], cps))

  | BBDCL_cstruct (vs,cps, reqs) -> 
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let cps = List.map (fun (name,argt) -> name,mt vars argt) cps in
    let reqs = fixup_reqs syms bsym_table vars polyinst reqs in
    Some (bbdcl_cstruct ([], cps, reqs))

  | BBDCL_struct (vs,cps)  -> 
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let cps = List.map (fun (name,argt) -> name,mt vars argt) cps in
    Some (bbdcl_struct ([], cps))


  | BBDCL_const_ctor (vs,uidx,ut,ctor_idx,evs,etraint) ->
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let ut = mt vars ut in
    let uidx = find_felix_inst syms bsym_table processed to_process nubids uidx ts in
    Some (bbdcl_const_ctor ([],uidx,ut,ctor_idx,evs,etraint)) (* ignore GADT stuff *)
 
  | BBDCL_nonconst_ctor (vs,uidx,ut,ctor_idx,ctor_argt,evs,etraint) ->
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let ut = mt vars ut in
    let uidx = find_felix_inst syms bsym_table processed to_process nubids uidx ts in
    let ctor_argt = mt vars ctor_argt in
    Some (bbdcl_nonconst_ctor ([],uidx, ut,ctor_idx,ctor_argt,evs,etraint)) (* ignore GADT stuff *)
 

  | BBDCL_typeclass _ -> assert false
  | BBDCL_instance _ -> assert false

  | BBDCL_axiom 
  | BBDCL_lemma 
  | BBDCL_reduce -> assert false 

  | BBDCL_invalid  -> assert false

  | BBDCL_newtype (vs,t) ->  
(*
print_endline ("ADJUSTING NEWTYPE " ^Flx_bsym.id bsym );
*)
    assert (List.length vs = List.length ts);
    let vars = List.map2 (fun (s,i) t -> i,t) vs ts in
    let t = mt vars t in
    Some (bbdcl_newtype ([],t))
  
  | BBDCL_module -> assert false


let rec mono_element debug syms to_process processed bsym_table nutab nubids i ts j =
(*
  print_endline ("mono_element: " ^ si i ^ "[" ^ catmap "," (sbt bsym_table) ts ^ "]" ^ " --> " ^ si j);
*)
  let virtualinst i ts =
    try Flx_typeclass.maybe_fixup_typeclass_instance syms bsym_table i ts 
    with Not_found -> 
      print_endline ("[mono-element:virtualinst] Can't find index " ^ si i); 
      if BidSet.mem i (!nubids) then begin
        print_endline "FOUND IN NEW TABLE .. OK";
        i,ts
      end else
        assert false
  in

  let polyinst i ts =  
    let sym = 
      try Some (Flx_bsym_table.find bsym_table i)
      with Not_found ->
         print_endline ("[mono-element:polyinst] Can't find index " ^ si i); 
         if BidSet.mem i (!nubids) then begin
           print_endline "FOUND IN NEW TABLE .. OK";
           None
         end else
         assert false
    in
    match sym with
    | None -> assert (ts = []); i, ts
    | Some sym ->
    let {Flx_bsym.id=id;sr=sr; bbdcl=bbdcl} = sym in
    match bbdcl with
    | BBDCL_external_type _ 
    | BBDCL_external_const _ 
    | BBDCL_external_fun _ 
    | BBDCL_external_code _  -> 
      let j = find_felix_inst syms bsym_table processed to_process nubids i ts in
      j,ts
    | _ ->
      let j = find_felix_inst syms bsym_table processed to_process nubids i ts in
      j,[]
  in
  begin try List.iter (check_mono bsym_table) ts with _ -> assert false end;
  try
    let parent,sym = 
      try Flx_bsym_table.find_with_parent bsym_table i 
      with Not_found -> assert false
    in
    let {Flx_bsym.id=id;sr=sr;bbdcl=bbdcl} = sym in
    let parent = match parent with
      | None -> None
      | Some 0 -> Some 0 
      | Some p -> 
        let psym = 
          try Flx_bsym_table.find bsym_table p 
          with Not_found -> 
            print_endline ("[mono_element] Cannot find parent " ^ si p);
            assert false 
        in
        let {Flx_bsym.id=id;sr=sr;bbdcl=bbdcl} = psym in
        begin match bbdcl with
        | BBDCL_fun (_,vs,_,_,_) ->
          let n = List.length vs in
          let pts = Flx_list.list_prefix ts n in 
(*
print_endline ("Our ts = " ^ catmap "," (sbt bsym_table) ts);
print_endline ("Parent vs = " ^ catmap "," (fun (s,i) -> s) vs);
print_endline ("Parent ts = " ^ catmap "," (sbt bsym_table) pts);
*)
(*
          print_endline ("  mono_element: adding parent " ^ si p ^" = " ^ id ^ ", ts=" ^ catmap "," (sbt bsym_table) pts);
*)
          let nuparent = find_felix_inst syms bsym_table processed to_process nubids p pts in
(*
          print_endline ("Nu parent: " ^ si nuparent);
*)
          Some nuparent

        | BBDCL_instance _
        | BBDCL_module
        | BBDCL_typeclass _ -> None
        | _ -> assert false 
        end
    in
    let maybebbdcl = 
      try mono_bbdcl syms bsym_table processed to_process nubids virtualinst polyinst ts sym 
      with Not_found -> assert false 
    in
    begin match maybebbdcl with
    | Some nubbdcl -> 
      let nusym ={Flx_bsym.id=id; sr=sr; bbdcl=nubbdcl} in
      Flx_bsym_table.add nutab j parent nusym
    | None -> ()
    end
  with Not_found -> 
   print_endline "NOT FOUND in mono_element";
   raise Not_found

let monomorphise2 debug syms bsym_table =
(*
    print_endline "";
    print_endline "---------------------------";
    print_endline "PRE NUMONO";
    print_endline "---------------------------";
    print_endline "";

    Flx_print.print_bsym_table bsym_table;
*)
  let roots: BidSet.t = !(syms.roots) in
  assert (BidSet.cardinal roots > 0);


  (* to_process is the set of symbols yet to be scanned
     searching for symbols to monomorphise
  *)
  let to_process = ref MonoMap.empty in
  BidSet.iter (fun i -> to_process := MonoMap.add (i,[]) (i) (!to_process)) roots;
  
  let processed = ref MonoMap.empty in

  (* new bsym_table *)
  let nutab = Flx_bsym_table.create () in

  (* Set of indices of NEW symbols to go or already gone into it *)
  let nubids = ref  BidSet.empty in 


  while not (MonoMap.is_empty (!to_process)) do
    let (i,ts),j = MonoMap.choose (!to_process) in
    assert (not (MonoMap.mem (i,ts) (!processed) ));
    begin try List.iter (check_mono bsym_table) ts with _ -> assert false end;

    to_process := MonoMap.remove (i,ts) (!to_process);
    processed := MonoMap.add (i,ts) j (!processed);

    (*
    (* if i <> j then *)
      print_endline ("numono: "^showts bsym_table i ts ^" ==> " ^ si j);
    *)
    assert (List.length ts > 0 || i == j);
    assert (not (Flx_bsym_table.mem nutab j));
    mono_element debug syms to_process processed bsym_table nutab nubids i ts j;

     
  done
  ;

  Hashtbl.clear syms.instances_of_typeclass;
  Hashtbl.clear syms.virtual_to_instances;
  syms.axioms := [];
  syms.reductions := [];
  if syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then 
  begin
    print_endline "";
    print_endline "---------------------------";
    print_endline "POST NUMONO";
    print_endline "---------------------------";
    print_endline "";

    Flx_print.print_bsym_table nutab
  end;

  nutab

