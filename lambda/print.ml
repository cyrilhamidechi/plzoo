(** Pretty-printing of expressions with the Ocaml [Format] library. *)

(** Print an expression, possibly placing parentheses around it. We always
    print things at a given "level" [at_level]. If the level exceeds the
    maximum allowed level [max_level] then the expression should be parenthesized.

    Let us consider an example. When printing nested applications, we should print [App
    (App (e1, e2), e3)] as ["e1 e2 e3"] and [App(e1, App(e2, e3))] as ["e1 (e2 e3)"]. So
    if we assign level 1 to applications, then during printing of [App (e1, e2)] we should
    print [e1] at [max_level] 1 and [e2] at [max_level] 0.
*)
let print ?(max_level=9999) ?(at_level=0) ppf =
  if max_level < at_level then
    begin
      Format.fprintf ppf "(@[" ;
      Format.kfprintf (fun ppf -> Format.fprintf ppf "@])") ppf
    end
  else
    begin
      Format.fprintf ppf "@[" ;
      Format.kfprintf (fun ppf -> Format.fprintf ppf "@]") ppf
    end

(** Print the given source code position. *)
let position loc ppf =
  match loc with
  | Common.Nowhere ->
      Format.fprintf ppf "unknown position"
  | Common.Position (begin_pos, end_pos) ->
      let begin_char = begin_pos.Lexing.pos_cnum - begin_pos.Lexing.pos_bol in
      let end_char = end_pos.Lexing.pos_cnum - begin_pos.Lexing.pos_bol in
      let begin_line = begin_pos.Lexing.pos_lnum in
      let filename = begin_pos.Lexing.pos_fname in

      if String.length filename != 0 then
        Format.fprintf ppf "file %S, line %d, charaters %d-%d" filename begin_line begin_char end_char
      else
        Format.fprintf ppf "line %d, characters %d-%d" (begin_line - 1) begin_char end_char

(** Print a sequence of things with the given (optional) separator. *)
let sequence ?(sep="") f lst ppf =
  let rec seq = function
    | [] -> print ppf ""
    | [x] -> print ppf "%t" (f x)
    | x :: xs -> print ppf "%t%s@ " (f x) sep ; seq xs
  in
    seq lst

(** Print an identifier *)
let ident x ppf =
  print ppf "%s" x

(** [lambda e ppf] prints abstraction using formatter [ppf]. *)
let rec lambda xs y e ppf =
  let rec collect ((e',_) as e) =
    match e' with
      | Syntax.Subst (s, e) -> let e = Syntax.subst s e in collect e
      | Syntax.Lambda (y, e) -> 
        let ys, k, e = collect e in ((y,k) :: ys), k+1, e
      | Syntax.Var _ | Syntax.App _ -> [], 0, e
  in
  let ys, k, e = collect e in
  let ys = (y, k) :: ys in
  let (ys, _) =
    List.fold_right
      (fun (y,k) (ys, xs) ->
        let y = (if Syntax.occurs k e then Beautify.refresh y xs else "_") in
          (y::ys, y::xs))
      ys ([], xs)
  in
  let xs = (List.rev ys) @ xs
  in
    print ~at_level:3 ppf "λ %t .@ %t" (sequence ident ys) (expr xs e)

(** [expr ctx e ppf] prints expression [e] using formatter [ppf]. *)
and expr ?max_level xs e ppf =
  let rec expr ?max_level xs (e, _) ppf = expr' ?max_level xs e ppf
  and expr' ?max_level xs e ppf =
    let print ?at_level = print ?max_level ?at_level ppf in
      if not (Format.over_max_boxes ()) then
        match e with
          | Syntax.Var k -> print "%s" (List.nth xs k)
          | Syntax.Subst (s, e) -> let e = Syntax.subst s e in print "%t" (expr ?max_level xs e)
          | Syntax.Lambda (y, e) -> print ~at_level:3 "%t" (lambda xs y e)
          | Syntax.App (e1, e2) -> print ~at_level:1 "%t@ %t" (expr ~max_level:1 xs e1) (expr ~max_level:0 xs e2)
  in
    expr ?max_level xs e ppf
    
let expr' xs e ppf = expr xs (Common.nowhere e) ppf

(** Support for printing of errors, warning and debugging information. *)

let verbosity = ref 2

let message ?(loc=Common.Nowhere) msg_type v =
  if v <= !verbosity then
    begin
      Format.eprintf "%s at %t:@\n@[" msg_type (position loc) ;
      Format.kfprintf (fun ppf -> Format.fprintf ppf "@]@.") Format.err_formatter
    end
  else
    Format.ifprintf Format.err_formatter

let error (loc, err_type, msg) = message ~loc (err_type) 1 "%s" msg
let warning msg = message "Warning" 2 msg
let debug msg = message "Debug" 3 msg