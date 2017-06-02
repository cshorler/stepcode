%option stack noyywrap nodefault
%option reentrant bison-bridge bison-locations
%option prefix="p1"

%top {
#define yylex_init p1lex_init
}

%{

#include "p1parser.h"

#define YY_USER_ACTION \
    yylloc_param->first_line = yylloc_param->last_line; \
    yylloc_param->first_column = yylloc_param->last_column; \
    for(int i = 0; yytext[i] != '\0'; i++) { \
        if(yytext[i] == '\n') { \
            yylloc_param->last_line++; \
            yylloc_param->last_column = 0; \
        } \
        else { \
            yylloc_param->last_column++; \
        } \
    }
    
/* TODO: there should be some way to use ... / __VA_ARGS__ to good effect here */
#define error(fmt) \
    do { fprintf(stderr, "line %i: " fmt, yylloc_param->first_line); } while (0)

const char *keywords[] = {
    "END_SUBTYPE_CONSTRAINT", "SUBTYPE_CONSTRAINT", "GENERIC_ENTITY", "END_PROCEDURE", "VALUE_UNIQUE", "END_FUNCTION",
    "END_CONSTANT", "ENUMERATION", "TOTAL_OVER", "EXTENSIBLE", "END_SCHEMA", "END_REPEAT", "END_ENTITY", "SUPERTYPE",
    "REFERENCE", "PROCEDURE", "END_LOCAL", "END_ALIAS", "AGGREGATE", "VALUE_IN", "OPTIONAL", "FUNCTION", "END_TYPE",
    "END_RULE", "END_CASE", "CONSTANT", "BASED_ON", "ABSTRACT", "UNKNOWN", "SUBTYPE", "ROLESOF", "RENAMED", "LOINDEX",
    "LOGICAL", "LOBOUND", "INVERSE", "INTEGER", "HIINDEX", "HIBOUND", "GENERIC", "CONST_E", "BOOLEAN",
    "BLENGTH", "USEDIN", "UNIQUE", "TYPEOF", "STRING", "SIZEOF", "SELECT", "SCHEMA", "RETURN", "REPEAT", "REMOVE",
    "NUMBER", "LENGTH", "INSERT", "FORMAT", "EXISTS", "ESCAPE", "ENTITY", "END_IF", "DERIVE", "BINARY", "WHILE", "WHERE",
    "VALUE", "UNTIL", "QUERY", "ONEOF", "LOG10", "LOCAL", "FIXED", "FALSE", "BEGIN", "ARRAY", "ANDOR", "ALIAS", "WITH",
    "TYPE", "TRUE", "THEN", "SQRT", "SKIP", "SELF", "RULE", "REAL", "LOG2", "LIST", "LIKE", "FROM", "ELSE", "CASE",
    "ATAN", "ASIN", "ACOS", "XOR", "VAR", "USE", "TAN", "SIN", "SET", "ODD", "NVL", "NOT", "MOD", "LOG", "FOR", "EXP",
    "END", "DIV", "COS", "BAG", "AND", "ABS", "TO", "OR", "OF", "IN", "IF", "BY", "AS",
    NULL
};

%}

WHITESPACE [ \t\n\r]
NOT_WHITESPACE [^ \t\n\r]
NOT_BREAK [^ \t\n\r;]
NOT_PAREN_STAR  [][:alnum:]!"'#$%&+,./:;<=>?@[\\^_'{|}~ \t\r-]

%x ID
%x REMARK

%%
    int comment_nesting = 0;

<ID,INITIAL>"(*"             { yy_push_state(REMARK, yyscanner); }

<REMARK>{
  "(*"           { ++comment_nesting; }
  "*"+")"        { if (comment_nesting) --comment_nesting; 
                   else yy_pop_state(yyscanner); }
  "*"+           ;
  {NOT_PAREN_STAR}+ ;
  [)(]           ;
  \n             ; /* flex ?optimisation? */
}

--[[:graph:] \t\r]*\n ; /* tail remark */

-- {
    error("invalid characters in tail remark!");
    return INVALID;
}

'(''|[^'\n])*' ; /* string literals */

' {
    error("invalid string literal!");
    return INVALID;
}

    /* match embedded keywords and discard */
{NOT_BREAK}(?i:END_)?(?i:SCHEMA|ENTITY|TYPE|FUNCTION|PROCEDURE|RULE){NOT_BREAK} ;
{NOT_BREAK}(?i:END_)?(?i:SCHEMA|ENTITY|TYPE|FUNCTION|PROCEDURE|RULE) ;
(?i:END_)?(?i:SCHEMA|ENTITY|TYPE|FUNCTION|PROCEDURE|RULE){NOT_BREAK} ;

    /* check for ';' here as we do not send the parser any ';' */
(?i:END_SCHEMA)/{WHITESPACE}*[;] { return END_SCHEMA; }
(?i:END_ENTITY)/{WHITESPACE}*[;] { return END_ENTITY; }
(?i:END_TYPE)/{WHITESPACE}*[;] { return END_TYPE; }
(?i:END_FUNCTION)/{WHITESPACE}*[;] { return END_FUNCTION; }
(?i:END_PROCEDURE)/{WHITESPACE}*[;] { return END_PROCEDURE; }
(?i:END_RULE)/{WHITESPACE}*[;] { return END_RULE; }

(?i:SCHEMA)/{WHITESPACE} {
    yy_push_state(ID, yyscanner);
    return SCHEMA;
}
(?i:ENTITY)/{WHITESPACE} {
    yy_push_state(ID, yyscanner);
    return ENTITY;
}
(?i:TYPE)/{WHITESPACE} {
    yy_push_state(ID, yyscanner);
    return TYPE;
}
(?i:FUNCTION)/{WHITESPACE} {
    yy_push_state(ID, yyscanner);
    return FUNCTION;
}
(?i:PROCEDURE)/{WHITESPACE} {
    yy_push_state(ID, yyscanner);
    return PROCEDURE;
}
(?i:RULE)/{WHITESPACE} {
    yy_push_state(ID, yyscanner);
    return RULE;
}

<ID>[[:alpha:]][[:alnum:]_]* {
    yy_pop_state(yyscanner);
    yylval->id = strdup(yytext);
    for (int i=0; keywords[i] != NULL; i++) {
        if (!strcasecmp(yytext, keywords[i])) {
            error("invalid identifier - express keywords are not allowed as identifiers!");
            return INVALID;
        }
    }
    return SIMPLE_ID;
}

<ID>{NOT_WHITESPACE} {
    error("invalid identifier - check character!");
    return INVALID;
}

<ID>{WHITESPACE} ;

<*>.|\n ;

%%
