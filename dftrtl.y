/*
 * File   : dftrtl.y
 * Author : Sandeep Koranne (C) 2026. All rights reserved.
 * Purpose: Lex/Yacc translator from C to System Verilog.
 *        : given filter code from SPIRAL convert to Verilog, and fixed point.
 */
%{
  /* -------------------------------------------------
     C‑side includes and data structures
     ------------------------------------------------- */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
  /* default prototype for the scanner */
  extern int yylex(void);

  /* declaration of the global input file used by the scanner */
  extern FILE *yyin;
  int yywrap(void) {
    return 1;
  }
  void yyerror(const char* msg) {
    fprintf(stderr, "error: %s\n",msg);
  }
#define MAX_LINE 1024
  char cur_line[MAX_LINE];      /* null‑terminated line text */
  int  cur_line_no = 1;         /* starts at 1 */

#define MAX_NAME 64

  /* Expression node */
  typedef enum { EX_NUM, EX_VAR, EX_ADD, EX_SUB, EX_MUL, EX_DIV, EX_NEG } ExprKind;
  typedef struct Expr {
    ExprKind kind;
    char *name;               /* for EX_VAR */
    char *num;                /* for EX_NUM */
    struct Expr *left;
    struct Expr *right;
    struct Expr *child; /* for EX_NEG unary minus */  
  } Expr;

  /* Statement node (only simple assignment) */
  typedef struct Stmt {
    char *lhs;                /* left‑hand side variable */
    Expr *rhs;                /* right‑hand side expression */
    struct Stmt *next;
  } Stmt;

  /* Global list of statements */
  Stmt *stmt_list = NULL;

  /* Helper prototypes */
  Expr *mk_expr_num(const char *s);
  Expr *mk_expr_var(const char *s);
  Expr *mk_expr_unary(ExprKind k, Expr *e);  
  Expr *mk_expr_bin(ExprKind k, Expr *l, Expr *r);
  void add_stmt(const char *lhs, Expr *rhs);
  void free_ast(void);
  void free_expr(Expr *);
  void emit_verilog(const char*, int, int, FILE *out);
  %}

%locations

 /* -------------------------------------------------
    Bison token declarations
    ------------------------------------------------- */
%union {
  char *str;
  struct Expr *expr;
  struct Stmt *stmt;
}

%destructor { free($$); } <str>      /* frees the strdup’d string */
%destructor { free_expr($$); } <expr>   /* frees the whole AST */
%destructor { free($$); } <lhs>      /* same as <str> – just a name copy */

 /* Tokens */
%token <str> ID NUM
%token VOID DOUBLE INT FLOAT
%token ASSIGN PLUS MINUS MUL DIV UMINUS
%token LPAREN RPAREN LBRACK RBRACK COMMA SEMICOLON LCURLY RCURLY

%type <expr> expr primary
%type <stmt> stmt
%type <str>  target 
 /* Operator precedence (same as C) */
%left PLUS MINUS
%left MUL DIV
%right UMINUS
%%

 /* -------------------------------------------------
    Grammar
    ------------------------------------------------- */
translation_unit
: function_def
;

function_def
: VOID ID LPAREN param_list RPAREN compound_stmt
{ /* nothing to do – all statements are already collected */ }
;

param_list
: /* empty */                         /* no parameters */
| param_decl
| param_list COMMA param_decl
;

param_decl
: DOUBLE ID LBRACK RBRACK            { /* treat X[] or _Y[] as a port – just record name */ }
| DOUBLE ID                          { /* scalar argument – same handling */ }
;

/* ---- compound statement (just a block of assignments) ---- */
compound_stmt
: LCURLY stmt_seq RCURLY
;

stmt_seq
: /* empty */
| stmt_seq stmt
;

stmt
: target ASSIGN expr SEMICOLON
{ add_stmt($1, $3); free($1); }
;

/* --------------------------------------------------------------
   New `target` rule – allows simple ID or indexed ID on the LHS
   -------------------------------------------------------------- */
target
: NUM ASSIGN expr SEMICOLON   {
  fprintf(stderr, "\n Assignment to literal.\n");
 }
| ID                       { $$ = strdup($1); }
| ID LBRACK expr RBRACK    {
  char buf[256];
  snprintf(buf, sizeof(buf), "%s[%s]",
	   $1,
	   $3->kind == EX_NUM ? $3->num : "???");
  $$ = strdup(buf);
  free($1);
  free_expr($3);
 }
;

stmt
: ID ASSIGN expr SEMICOLON
{ add_stmt($1, $3); free($1); } |
	
;

/* ---- expression grammar ---- */
expr
: MINUS expr %prec UMINUS   { $$ = mk_expr_unary(EX_NEG, $2); } 
| expr PLUS expr      { $$ = mk_expr_bin(EX_ADD, $1, $3); }
| expr MINUS expr     { $$ = mk_expr_bin(EX_SUB, $1, $3); }
| expr MUL expr       { $$ = mk_expr_bin(EX_MUL, $1, $3); }
| expr DIV expr       { $$ = mk_expr_bin(EX_DIV, $1, $3); }
| primary
;

primary
: NUM                 { $$ = mk_expr_num($1); free($1); }
| ID                  { $$ = mk_expr_var($1); free($1); }
| ID LBRACK expr RBRACK
{
  /* treat array access as a variable with an index.
     We encode it as a string "name[expr]" for later printing. */
  char buf[256];
  snprintf(buf, sizeof(buf), "%s[%s]", $1, $3->num ? $3->num : "???");
  $$ = mk_expr_var(strdup(buf));
  free($1);
  /* the index expression is not needed any more for this simple backend */
  free($3);
}
| LPAREN expr RPAREN  { $$ = $2; }
;

%%

  /* -------------------------------------------------
     Helper functions (AST construction & cleanup)
     ------------------------------------------------- */
Expr *mk_expr_num(const char *s) {
  Expr *e = calloc(1, sizeof(Expr));
  e->kind = EX_NUM;
  if(strlen(s) > 5) {
    int v = (1<<16) * strtod(s,NULL);
    //fprintf(stderr,"\n Quantization OPPORTUNITY: %s -> %d\n", s,v);
    e->num = calloc(16,sizeof(char));
    sprintf(e->num,"%d",v);
  } else {
    e->num  = strdup(s);
  }
  return e;
}
Expr *mk_expr_var(const char *s) {
  Expr *e = calloc(1, sizeof(Expr));
  e->kind = EX_VAR;
  e->name = strdup(s);
  return e;
}
Expr *mk_expr_bin(ExprKind k, Expr *l, Expr *r) {
  Expr *e = calloc(1, sizeof(Expr));
  e->kind = k;
  e->left = l;
  e->right = r;
  return e;
}
Expr *mk_expr_unary(ExprKind k, Expr *e)
{
  Expr *node = calloc(1, sizeof(Expr));
  node->kind  = k;        /* must be EX_NEG */
  node->child = e;        /* the operand */
  return node;
}
void add_stmt(const char *lhs, Expr *rhs) {
  Stmt *s = calloc(1, sizeof(Stmt));
  s->lhs = strdup(lhs);
  s->rhs = rhs;
  s->next = NULL;

  if (!stmt_list) {
    stmt_list = s;
  } else {
    Stmt *p = stmt_list;
    while (p->next) p = p->next;
    p->next = s;
  }
}
void free_expr(Expr *e) {
  if (!e) return;
  free(e->num);
  free(e->name);
  free_expr(e->left);
  free_expr(e->right);
  free_expr(e->child);
  free(e);
}
void free_ast(void) {
  Stmt *s = stmt_list;
  while (s) {
    Stmt *next = s->next;
    free(s->lhs);
    free_expr(s->rhs);
    free(s);
    s = next;
  }
}

/* -------------------------------------------------
   Verilog emission
   ------------------------------------------------- */
static void emit_expr(FILE *out, Expr *e) {
  if (!e) return;
  switch (e->kind) {
  case EX_NUM:   fprintf(out, "%s", e->num); break;
  case EX_VAR:   fprintf(out, "%s", e->name); break;
  case EX_ADD:   fprintf(out, "("); emit_expr(out, e->left);
    fprintf(out, " + "); emit_expr(out, e->right);
    fprintf(out, ")"); break;
  case EX_SUB:   fprintf(out, "("); emit_expr(out, e->left);
    fprintf(out, " - "); emit_expr(out, e->right);
    fprintf(out, ")"); break;
  case EX_MUL:   fprintf(out, "("); emit_expr(out, e->left);
    fprintf(out, " * "); emit_expr(out, e->right);
    fprintf(out, ")"); break;
  case EX_DIV:   fprintf(out, "("); emit_expr(out, e->left);
    fprintf(out, " / "); emit_expr(out, e->right);
    fprintf(out, ")"); break;
  case EX_NEG:   fprintf(out, "(-");      /* open parenthesis + minus */
    emit_expr(out, e->child);
    fprintf(out, ")"); break;		       
  }
}

/* Simple heuristic: any identifier that appears as a left‑hand side
   becomes a wire, any identifier that appears in a parameter list
   becomes a port.
   wire. */
void emit_verilog(const char* moduleName, int bitWidth, int vectorSize, FILE *out) {
  int opBitwidth = bitWidth * vectorSize;
  //fprintf(out, "`timescale 1ns/1ps\n");
  fprintf(out,"// C-code to Verilog translation by Sandeep Koranne\n");
  fprintf(out, "module %s (\n", moduleName);
  /* ---- ports ------------------------------------------------------- */
  /* In a real implementation you would collect the names that appear
     inside the parameter list (X, _Y).  For brevity we hard‑code them
     here – adjust to your own function signature. */
  fprintf(out, "    input logic clk,\n");
  fprintf(out, "    input logic reset,\n");    
  fprintf(out, "    input logic [%d:0] X_packed,   // 32‑point input vector\n", opBitwidth-1);
  fprintf(out, "    output logic [%d:0] Y_packed   // 32‑point output vector\n", opBitwidth-1);
  fprintf(out, ");\n\n");

  fprintf(out, "      logic [%d:0] X_input_reg;\n", opBitwidth-1);
  fprintf(out, "      logic [%d:0] Y_output;\n", opBitwidth-1);    
  fprintf(out, "      logic [%d:0]X[%d:0];\n",bitWidth-1,vectorSize-1);
  fprintf(out, "      logic [%d:0]Y[%d:0];\n",bitWidth-1,vectorSize-1);  
#define G_OUTPUT(opstr) fprintf(out, "            %s\n", opstr);
  G_OUTPUT("always_ff @(posedge clk) begin");
  G_OUTPUT("        if (reset)");
  fprintf(out,"             X_input_reg <= %d'h0;\n", opBitwidth);  
  G_OUTPUT("      else");
  G_OUTPUT("          X_input_reg <= X_packed;");
  G_OUTPUT("  end\n");
  G_OUTPUT(" genvar i;");
  G_OUTPUT("   generate");
  fprintf(out,"      for (i = 0; i < %d; i = i + 1) begin : unpackX\n", vectorSize);
  fprintf(out," 	  assign X[i] = X_input_reg[i*%d +: %d];\n",vectorSize,bitWidth);
  G_OUTPUT("      end");
  G_OUTPUT("   endgenerate");
  G_OUTPUT("   generate");
  fprintf(out,"      for (i = 0; i < %d; i = i + 1) begin : unpackY\n",vectorSize);
  G_OUTPUT(" 	  always_comb begin");
  fprintf(out," 	     Y_output[i*%d +: %d] = Y[i];\n",vectorSize,bitWidth);
  G_OUTPUT(" 	  end");
  G_OUTPUT("      end");
  G_OUTPUT("   endgenerate");
  G_OUTPUT(" always_ff @(posedge clk) begin");
  G_OUTPUT("       if (reset)");
  fprintf(out,"         Y_packed <= %d'h0;\n",opBitwidth);
  G_OUTPUT("       else");
  G_OUTPUT("           Y_packed <= Y_output;");
  G_OUTPUT("   end");

#undef G_OUTPUT  
  /* ---- declare all temporaries as wires -------------------------------- */
  Stmt *s = stmt_list;
  while (s) {
    if( strncmp(s->lhs,"Y",1) != 0) fprintf(out, "logic signed [%d:0] %s;\n", bitWidth-1,s->lhs);
    s = s->next;
  }
  fprintf(out, "\n");

  /* ---- generate assignments ------------------------------------------- */
  s = stmt_list;
  while (s) {
    fprintf(out, "assign %s = ", s->lhs);
    emit_expr(out, s->rhs);
    fprintf(out, ";\n");
    s = s->next;
  }

  fprintf(out, "\nendmodule\n");
}

/* -------------------------------------------------
   Main driver
   ------------------------------------------------- */
int main(int argc, char **argv) {
  int bitWidth = 31;
  int vectorSize = 31;
  if (argc < 3) {
    fprintf(stderr, "Usage: %s <c_source> ModuleName BitWidth [31] VectorSize[31]\n", argv[0]);
    return 1;
  }
  const char* moduleName = NULL;
  if( argc > 2 ) {
    moduleName = argv[2];
  }
  if( argc > 3 ) {
    bitWidth = strtod( argv[3], NULL );
  }
  if( argc > 4 ) {
    vectorSize = strtod( argv[4], NULL );
  }
  
  FILE *in = fopen(argv[1], "r");
  if (!in) { perror("fopen"); return 1; }
  yyin = in;

  if (yyparse() == 0) {
    /* parsing succeeded – emit Verilog to stdout */
    emit_verilog(moduleName,bitWidth,vectorSize, stdout);
  } else {
    fprintf(stderr, "Parse error!\n");
  }

  free_ast();
  fclose(in);
  return 0;
}
