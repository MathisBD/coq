(************************************************************************)
(*         *      The Rocq Prover / The Rocq Development Team           *)
(*  v      *         Copyright INRIA, CNRS and contributors             *)
(* <O___,, * (see version control and CREDITS file for authors & dates) *)
(*   \VV/  **************************************************************)
(*    //   *    This file is distributed under the terms of the         *)
(*         *     GNU Lesser General Public License Version 2.1          *)
(*         *     (see LICENSE file for the text of the license)         *)
(************************************************************************)

open Procq

type proof_mode_entry = ProofMode : {
  command_entry : Vernacexpr.vernac_expr Entry.t;
  wit_tactic_expr : ('raw,_,unit) Genarg.genarg_type;
  tactic_expr_entry : 'raw Entry.t;
} -> proof_mode_entry

type proof_mode = string

(* Tactic parsing modes *)
let register_proof_mode, find_proof_mode, lookup_proof_mode, list_proof_modes =
  let proof_mode : (string, proof_mode_entry) Hashtbl.t =
    Hashtbl.create 19 in
  let register_proof_mode ename e = Hashtbl.add proof_mode ename e; ename in
  let find_proof_mode ename =
    try Hashtbl.find proof_mode ename
    with Not_found ->
      CErrors.anomaly Pp.(str "proof mode not found: " ++ str ename) in
  let lookup_proof_mode name =
    if Hashtbl.mem proof_mode name then Some name
    else None
  in
  let list_proof_modes () =
    Hashtbl.fold CString.Map.add proof_mode CString.Map.empty
  in
  register_proof_mode, find_proof_mode, lookup_proof_mode, list_proof_modes

let proof_mode_to_string name = name

(* Default proof mode, to be set at the beginning of proofs for
   programs that cannot be statically classified. *)
let proof_mode_opt_name = ["Default";"Proof";"Mode"]

let noedit_mode = Entry.make "noedit_command"
let noedit_tactic_expr = Entry.make "noedit_tactic_expr"

let noedit_mode_entry = ProofMode {
  command_entry = noedit_mode;
  wit_tactic_expr = Stdarg.wit_unit;
  tactic_expr_entry = noedit_tactic_expr;
}

let { Goptions.get = get_default_proof_mode } =
  Goptions.declare_interpreted_string_option_and_ref
    ~stage:Summary.Stage.Synterp
    ~key:proof_mode_opt_name
    ~value:(register_proof_mode "Noedit" noedit_mode_entry)
    (fun name -> match lookup_proof_mode name with
    | Some pm -> pm
    | None -> CErrors.user_err Pp.(str (Format.sprintf "No proof mode named \"%s\"." name)))
    proof_mode_to_string
    ()

let command_entry_ref = ref None

module Vernac_ =
  struct
    (* The different kinds of vernacular commands *)
    let gallina = Entry.make "gallina"
    let gallina_ext = Entry.make "gallina_ext"
    let command = Entry.make "command"
    let syntax = Entry.make "syntax_command"
    let vernac_control = Entry.make "vernac_control"
    let inductive_or_record_definition = Entry.make "inductive_or_record_definition"
    let fix_definition = Entry.make "fix_definition"
    let red_expr = Entry.make "red_expr"
    let hint_info = Entry.make "hint_info"
    (* Main vernac entry *)
    let main_entry = Entry.make "vernac"
    let noedit_mode = noedit_mode

    let () =
      let act_vernac v loc = Some v in
      let act_eoi _ loc = None in
      let rule = [
        Procq.(Production.make (Rule.next Rule.stop (Symbol.token Tok.PEOI)) act_eoi);
        Procq.(Production.make (Rule.next Rule.stop (Symbol.nterm vernac_control)) act_vernac);
      ] in
      Procq.(grammar_extend main_entry (Fresh (Gramlib.Gramext.First, [None, None, rule])))

    let select_command_entry spec =
      match spec with
      | None -> noedit_mode
      | Some ename ->
        let ProofMode mode = find_proof_mode ename in
        mode.command_entry

    let parse_generic_tactic strm =
      let mode = get_default_proof_mode () in
      let ProofMode mode = find_proof_mode mode in
      let v = Procq.Entry.parse_token_stream mode.tactic_expr_entry strm in
      Gentactic.of_raw_genarg Genarg.(in_gen (rawwit mode.wit_tactic_expr) v)

    let command_entry =
      Procq.Entry.(of_parser "command_entry"
        { parser_fun = (fun _kwstate strm -> Procq.Entry.parse_token_stream (select_command_entry !command_entry_ref) strm) })

    let generic_tactic =
      Procq.Entry.(of_parser "generic_tactic"
        { parser_fun = (fun _kwstate strm -> parse_generic_tactic strm) })

  end

module Unsafe = struct
  let set_tactic_entry oname = command_entry_ref := oname
end

let main_entry proof_mode =
  Unsafe.set_tactic_entry proof_mode;
  Vernac_.main_entry

let () =
  register_grammar Redexpr.wit_red_expr (Vernac_.red_expr);
  register_grammar Gentactic.wit_generic_tactic Vernac_.generic_tactic
