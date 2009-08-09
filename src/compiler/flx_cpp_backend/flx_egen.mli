val gen_expr:
  Flx_mtypes2.sym_state_t ->
  Flx_types.fully_bound_symbol_table_t ->
  int ->
  Flx_types.tbexpr_t ->
  Flx_types.bvs_t ->
  Flx_types.btypecode_t list ->
  Flx_srcref.t -> string

val gen_expr':
  Flx_mtypes2.sym_state_t ->
  Flx_types.fully_bound_symbol_table_t ->
  int ->
  Flx_types.tbexpr_t ->
  Flx_types.bvs_t ->
  Flx_types.btypecode_t list ->
  Flx_srcref.t -> Flx_ctypes.cexpr_t

(* for use in an expression *)
val get_var_ref:
  Flx_mtypes2.sym_state_t ->
  Flx_types.fully_bound_symbol_table_t ->
  int ->
  int ->
  Flx_types.btypecode_t list ->
  string

(* for definition/initialisation *)
val get_ref_ref:
  Flx_mtypes2.sym_state_t ->
  Flx_types.fully_bound_symbol_table_t ->
  int ->
  int ->
  Flx_types.btypecode_t list ->
  string