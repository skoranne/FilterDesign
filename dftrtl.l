/*
 * File   : dftrtl.l
 * Author : Sandeep Koranne (C) 2026. All rights reserved.
 * Purpose: Lex/Yacc translator from C to System Verilog.
 *        : given filter code from SPIRAL convert to Verilog, and fixed point.

%option reentrant
%option bison-bridge
%option header-file="dftrtl_lex.h"
 */

%{
#include "dftrtl.tab.h"          /* Bison token definitions */
#include <string.h>
#include <stdlib.h>
%}
/* -------------------------------------------------
   Regular expressions
   ------------------------------------------------- */
DIGIT      [0-9]
LETTER     [a-zA-Z_]
ID         {LETTER}({LETTER}|{DIGIT})*
NUM        {DIGIT}+(\.{DIGIT}+)?([eE][+-]?{DIGIT}+)? 

/* -------------------------------------------------
   Rules
   ------------------------------------------------- */
%%

"void"                  { return VOID; }
"double"                { return DOUBLE; }
"int"                   { return INT; }
"float"                 { return FLOAT; }

"="                     { return ASSIGN; }
"+"                     { return PLUS; }
"-"                     { return MINUS; }
"*"                     { return MUL; }
"/"                     { return DIV; }
"{"                     { return LCURLY; }
"}"                     { return RCURLY; }
"("                     { return LPAREN; }
")"                     { return RPAREN; }
"["                     { return LBRACK; }
"]"                     { return RBRACK; }
","                     { return COMMA; }
";"                     { return SEMICOLON; }

{ID}                    { yylval.str = strdup(yytext); return ID; }
{NUM}                   { yylval.str = strdup(yytext); return NUM; }

[ \t\r\n]+              /* skip whitespace */
"/*"([^*]|\*+[^*/])*\*+"/"   /* skip block comments */
"//".*                  /* skip line comments */

.                       { fprintf(stderr,"[LEX] Unexpected character: %s\n",yytext); exit(1); }

%%
