%{
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

let loc () = Location.get_current ()

let build l bop e1 e2 = (* match bop, Q.compare e2 (Q.of_int 0) with *)
  (* | Ast.Minus, 0 -> e1 *)
  (* | _ ->  *)Ast.UBinop (l, bop, e1, e2)
		   
let build_op_eq l v bop e = Ast.UAsn (l, v, build l bop (Ast.UVar (l, v)) e)

      

%}

%token <Q.t * Ast.base_type> NUM
%token <string> VAR
%token LPAR RPAR SEMICOL LOWER_SEMICOL COMMA RAND_ITV EQUAL IF ELSE WHILE LBRA RBRA DBLPOINT
%token PLUS2 MINUS2
%token GT LT GE LE
%token PLUS MINUS TIMES DIV UMINUS
%token INTTYPE REALTYPE BOOLTYPE
%token SEQ
%token EOF

%nonassoc SEMICOL
%nonassoc LOWER_SEMICOL
%nonassoc VAR IF WHILE PLUS2 MINUS2
%nonassoc SEQ
%left PLUS MINUS
%left TIMES DIV
%nonassoc UMINUS

%type < Typing.typing_env * Ast.ustm> file
%start file

%%

file:
| decls stm EOF { $1 Typing.empty_env, $2 }

decls:
| vtype varlist SEMICOL decls {  
  fun env -> 
    let env = List.fold_left (Typing.decl_var_type $1) env $2 in
    $4 env
}

| vtype varlist SEMICOL { fun env -> List.fold_left (Typing.decl_var_type $1) env $2 }



vtype:
| INTTYPE { Ast.IntT }
| REALTYPE { Ast.RealT }
| BOOLTYPE { Ast.BoolT }
	   
varlist:
| VAR COMMA varlist { ($1,loc())::$3 }
| VAR { [$1, loc()] }
    
      
stm:
| VAR EQUAL expr SEMICOL { Ast.UAsn (loc (), $1, $3) }
| stm stm %prec SEQ { Ast.USeq (loc (), $1, $2) }
| IF LPAR comp RPAR LBRA stm RBRA ELSE LBRA stm RBRA
    { Ast.UIte (loc (), $3, $6, $10) }
| WHILE LPAR comp RPAR LBRA stm RBRA
    { Ast.UWhile (loc (), $3, $6) }
/* syntactic sugar : v *= e ~~> v = v * e */
| VAR PLUS EQUAL expr SEMICOL { build_op_eq (loc ()) $1 Ast.Plus $4 }
| VAR MINUS EQUAL expr SEMICOL { build_op_eq (loc ()) $1 Ast.Minus $4 }
| VAR TIMES EQUAL expr SEMICOL { build_op_eq (loc ()) $1 Ast.Times $4 }
| VAR DIV EQUAL expr SEMICOL { build_op_eq (loc ()) $1 Ast.Div $4 }
/* syntactic sugar : ++x ~~> x = x + 1 */
| PLUS2 VAR SEMICOL { build_op_eq (loc ()) $2 Ast.Plus (Ast.UCst (loc (), (Q.of_int 1, None))) }
| VAR PLUS2 SEMICOL { build_op_eq (loc ()) $1 Ast.Plus (Ast.UCst (loc (), (Q.of_int 1, None))) }
| MINUS2 VAR SEMICOL { build_op_eq (loc ()) $2 Ast.Minus (Ast.UCst (loc (), (Q.of_int 1, None))) }
| VAR MINUS2 SEMICOL { build_op_eq (loc ()) $1 Ast.Minus (Ast.UCst (loc (), (Q.of_int 1, None))) }


expr:
| NUM { let x, t = $1 in Ast.UCst (loc (), (x, Some t)) }
| VAR { Ast.UVar (loc (), $1) }
| RAND_ITV LPAR signed_num COMMA signed_num RPAR { 
  let x1, t1 = $3 and
      x2, t2 = $5 in
  if t1 = t2 then
    Ast.URand (loc (), t1, x1, x2)
  else
    failwith "range with different types"
}
| LPAR expr RPAR { $2 }
| expr PLUS expr { build (loc ()) Ast.Plus $1 $3 }
| expr MINUS expr { build (loc ()) Ast.Minus $1 $3 }
| expr TIMES expr { build (loc ()) Ast.Times $1 $3 }
| expr DIV expr { build (loc ()) Ast.Div $1 $3 }
/* syntactic sugar : -e ~~> 0 - e */
| MINUS expr %prec UMINUS { build (loc ()) Ast.Minus (Ast.UCst (loc (), (Q.of_int 0, None))) $2 }

/* everything rephrased as expr >= 0 or expr > 0 */
comp: 
| expr GT expr { build (loc ()) Ast.Minus $1 $3, Ast.Strict }
| expr LT expr { build (loc ()) Ast.Minus $3 $1, Ast.Strict }
| expr GE expr { build (loc ()) Ast.Minus $1 $3, Ast.Loose }
| expr LE expr { build (loc ()) Ast.Minus $3 $1, Ast.Loose }

signed_num:
| NUM { $1 }
| MINUS NUM { let x, t = $2 in Q.neg x, t }
