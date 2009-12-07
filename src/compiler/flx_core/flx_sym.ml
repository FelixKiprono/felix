(** The symbol type. *)
type t = {
  id:string;
  sr:Flx_srcref.t;
  parent:Flx_types.bid_t option;
  vs:Flx_types.ivs_list_t;
  pubmap:Flx_types.name_map_t;
  privmap:Flx_types.name_map_t;
  dirs:Flx_types.sdir_t list;
  symdef:Flx_types.symbol_definition_t;
}