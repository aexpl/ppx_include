(* #if OCAML_VERSION < (4, 03, 0) *)
(* #define Pconst_string Const_string *)
(* #endif *)

open Asttypes
open Parsetree
open Ast_mapper

let raise_errorf ?sub ?if_highlight ?loc message =
  message |> Printf.kprintf (fun str ->
    let err = Location.error ?sub ?if_highlight ?loc str in
    raise (Location.Error err))

let filename_of_payload ~loc payload =
  match payload with
  | PStr [{
    pstr_desc = Pstr_eval (
      { pexp_desc = Pexp_constant (Pconst_string (file, None)); _ },
      _);
      _
    }] ->
    file
  | _ ->
    raise_errorf ~loc "[%%include]: invalid syntax"

let lexbuf_of_payload ~loc payload =
  let filename = filename_of_payload ~loc payload in
  let load_paths =
    (Filename.dirname loc.Location.loc_start.Lexing.pos_fname :: !Config.load_path) |>
    List.map (fun dir -> Filename.concat dir filename)
  in
  try
    load_paths |>
    List.find (fun intf -> Sys.file_exists intf) |>
    open_in |>
    Lexing.from_channel
  with Not_found ->
    raise_errorf ~loc "[%%include]: cannot locate file %S" filename

let rec structure mapper items =
  match items with
  | { pstr_desc = Pstr_extension (({ txt = "include"; loc }, payload), _); _ } :: _ ->
    mapper.structure mapper (Parse.implementation (lexbuf_of_payload ~loc payload))
  | item :: items ->
    mapper.structure_item mapper item :: structure mapper items
  | [] -> []

let rec signature mapper items =
  match items with
  | { psig_desc = Psig_extension (({ txt = "include"; loc }, payload), _); _ } :: _ ->
    mapper.signature mapper (Parse.interface (lexbuf_of_payload ~loc payload))
  | item :: items ->
    mapper.signature_item mapper item :: signature mapper items
  | [] -> []

let () =
  Ast_mapper.register "ppx_include" (fun _ ->
    { default_mapper with structure; signature; })
