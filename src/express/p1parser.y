/*
 * The Pass 1 parser only needs to generate id and schema information for the Pass 2 parser
 *
 * Concretely this means parsing Scopes: schema_decl, entity_decl, type_decl, function_decl, procedure_decl, rule_decl
 * 
 * Ignoring the following scope types:  alias_stmt, query_expression, repeat_stmt, subtype_constraint_decl
 *
 */

%define api.prefix p1
%define api.pure full
%locations

%code requires {

#include <stdbool.h>

typedef struct p1data {
    char *exp_path;
    char *schema_id;
    char **entity_id_list;
    int entity_count;
    char **type_id_list;
    int type_count;
    char **function_id_list;
    int function_count;
    char **procedure_id_list;
    int procedure_count;
    char **rule_id_list;
    int rule_count;
    struct p1data *next;
} p1data_t;

typedef void* yyscan_t;

}

%parse-param {p1data_t *p1data_head}
%parse-param {yyscan_t scanner}
%lex-param {yyscan_t scanner}

%union {
    char *id;
    p1data_t *p1data_p;
}

%code provides {
#define YYSTYPE P1STYPE
#define YYLTYPE P1LTYPE
}


%token INVALID

%token SCHEMA ENTITY TYPE FUNCTION PROCEDURE RULE
       END_SCHEMA END_ENTITY END_TYPE END_FUNCTION END_PROCEDURE END_RULE

%token <id> SIMPLE_ID
%type <id> schema_id entity_id type_id function_id procedure_id rule_id
%type <p1data_p> schema_decl schema_decl_list

%start express_file

%{
#include <stdio.h>
#include <stdlib.h>

#include "p1lexer.h"

void yyerror(YYLTYPE *llocp, p1data_t *p1data_head, yyscan_t scanner, const char *msg);

p1data_t *p1data_current;

int entity_id_len;
int type_id_len;
int function_id_len;
int procedure_id_len;
int rule_id_len;

#define append(type, id) do { \
    p1data_current->type ## _count++; \
    if (p1data_current->type ## _count == type ## _id_len) { \
        type ## _id_len += 100; \
        p1data_current->type ## _id_list = realloc(p1data_current->type ## _id_list, type ## _id_len * sizeof(char *)); \
    } \
    p1data_current->type ## _id_list[p1data_current->type ## _count - 1] = id; \
    p1data_current->type ## _id_list[p1data_current->type ## _count] = NULL; \
    } while (0)

%}

%%

schema_decl: SCHEMA schema_id {
        entity_id_len = type_id_len = function_id_len = procedure_id_len = rule_id_len = 100;
        p1data_current = calloc(sizeof(p1data_t), 1);
        p1data_current->exp_path = p1data_head->exp_path;
        p1data_current->schema_id = $2;
        p1data_current->entity_id_list = malloc(entity_id_len * sizeof(char *));
        p1data_current->type_id_list = malloc(type_id_len * sizeof(char *));
        p1data_current->function_id_list = malloc(function_id_len * sizeof(char *));
        p1data_current->procedure_id_list = malloc(procedure_id_len * sizeof(char *));
        p1data_current->rule_id_list = malloc(rule_id_len * sizeof(char *));
        $<p1data_p>$ = p1data_current;
    } schema_body END_SCHEMA {
        $$ = $<p1data_p>3;
    }
        
function_decl: FUNCTION function_id {
        append(function, $2);
    } algorithm_head END_FUNCTION
    ;
	
procedure_decl: PROCEDURE procedure_id {
        append(procedure, $2);
    } algorithm_head END_PROCEDURE
    ;

rule_decl: RULE rule_id {
        append(rule, $2);
    } algorithm_head END_RULE
    ;

entity_decl: ENTITY entity_id END_ENTITY {
    append(entity, $2);
    }

type_decl: TYPE type_id END_TYPE {
    append(type, $2);
    }

schema_id: SIMPLE_ID ;
entity_id: SIMPLE_ID ;
type_id: SIMPLE_ID ;
function_id: SIMPLE_ID ;
procedure_id: SIMPLE_ID ;
rule_id: SIMPLE_ID ;

express_file: schema_decl_list ;

algorithm_head: /* empty */
              | algorithm_head declaration ;

schema_body: declaration_or_rule_decl_list ;

declaration: entity_decl | function_decl | procedure_decl | type_decl ;
declaration_or_rule_decl: declaration | rule_decl ;
			
declaration_or_rule_decl_list: declaration_or_rule_decl
                             | declaration_or_rule_decl_list declaration_or_rule_decl
                             ;

schema_decl_list: schema_decl {
        p1data_head->next = $1;
        $$ = $1;
    }
    | schema_decl_list schema_decl {
        $1->next = $2;
        $$ = $2;
    }

%%

void yyerror(YYLTYPE *llocp, p1data_t *p1data_head, yyscan_t scanner, const char *msg){
    fprintf(stderr, "%s\n", msg);
    fprintf(stderr, "file: %s line: %i column: %i\n", p1data_head->exp_path, llocp->first_line, llocp->first_column);
}

