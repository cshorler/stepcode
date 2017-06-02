/*
 *
 */
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>

#include "argparse.h"
#include "p1parser.h"
#include "p1lexer.h"

/* NOTE: dummy implementation for proof of concept only */
#ifdef EXP2CXX_CMAKE_HELPER
#define FMT_TYPE_H "%s.h"
#define FMT_TYPE_CC "%s.cc"
#define FMT_ENTITY_H "%s.h"
#define FMT_ENTITY_CC "%s.cc"
#define CMAKE_HELPER_HEADERS (1<<0)
#define CMAKE_HELPER_IMPLS (1<<1)
#endif

/* usage */
const char *usages[] = {
    "@EXPSS@ schemas EXP_PATH",
#ifdef EXP2CXX_CMAKE_HELPER
    "@EXPSS@ entities --schema NAME [--impls | --headers] EXP_PATH",
    "@EXPSS@ types --schema NAME [--impls | --headers] EXP_PATH",
#else
    "@EXPSS@ entities --schema NAME EXP_PATH",
    "@EXPSS@ types --schema NAME EXP_PATH",
#endif    
    "@EXPSS@ functions --schema NAME EXP_PATH",
    "@EXPSS@ procedures --schema NAME EXP_PATH",
    "@EXPSS@ rules --schema NAME EXP_PATH",
    NULL
};

int p1debug;

int process_schemas(char *exp_path) {
    p1data_t pd, *p1data_head = &pd;
    FILE *f;
    yyscan_t lexer;
    int rc;

    memset(p1data_head, 0, sizeof(p1data_t));
    p1data_head->exp_path = exp_path;
    
    f = fopen(exp_path, "r");
    p1lex_init(&lexer);
    p1set_in(f, lexer);
    rc = p1parse(p1data_head, lexer);
    if (rc)
        exit(EXIT_FAILURE);
    
    for (p1data_t *p = p1data_head->next; p != NULL; p = p->next)
        fprintf(stdout, "%s ", p->schema_id);

    fprintf(stdout, "\n");
    
    exit(EXIT_SUCCESS);
}

int process_functions(char *exp_path, char *schema_name) {
    p1data_t pd, *p1data_head = &pd;
    FILE *f;
    yyscan_t lexer;
    int rc;
    bool ok;

    memset(p1data_head, 0, sizeof(p1data_t));
    p1data_head->exp_path = exp_path;
    
    p1lex_init(&lexer);
    f = fopen(exp_path, "r");
    p1set_in(f, lexer);
    
    rc = p1parse(p1data_head, lexer);
    if (rc)
        exit(EXIT_FAILURE);
    
    ok = false;
    for (p1data_t *p = p1data_head->next; p != NULL; p = p->next) {
        if (!strcasecmp(p->schema_id, schema_name)) {
            ok = true;
            for (int i = 0; i < p->function_count; i++)
                fprintf(stdout, "%s\n", p->function_id_list[i]);
        }
    }
    
    if (!ok) {
        fprintf(stderr, "invalid schema: %s\n", schema_name);
        exit(EXIT_FAILURE);
    }
    exit(EXIT_SUCCESS);
}

int process_procedures(char *exp_path, char *schema_name) {
    p1data_t pd, *p1data_head = &pd;
    FILE *f;
    yyscan_t lexer;
    int rc;
    bool ok;

    memset(p1data_head, 0, sizeof(p1data_t));
    p1data_head->exp_path = exp_path;
    
    p1lex_init(&lexer);
    f = fopen(exp_path, "r");
    p1set_in(f, lexer);
    rc = p1parse(p1data_head, lexer);
    if (rc)
        exit(EXIT_FAILURE);

    ok = false;
    for (p1data_t *p = p1data_head->next; p != NULL; p = p->next) {
        if (!strcasecmp(p->schema_id, schema_name)) {
            ok = true;
            for (int i = 0; i < p->procedure_count; i++)
                fprintf(stdout, "%s\n", p->procedure_id_list[i]);
        }        
    }
    
    if (!ok) {
        fprintf(stderr, "invalid schema: %s\n", schema_name);
        exit(EXIT_FAILURE);
    }
    exit(EXIT_SUCCESS);
}

int process_rules(char *exp_path, char *schema_name) {
    p1data_t pd, *p1data_head = &pd;
    FILE *f;
    yyscan_t lexer;
    int rc;
    bool ok;

    memset(p1data_head, 0, sizeof(p1data_t));
    p1data_head->exp_path = exp_path;
    
    p1lex_init(&lexer);
    f = fopen(exp_path, "r");
    p1set_in(f, lexer);
    rc = p1parse(p1data_head, lexer);
    if (rc)
        exit(EXIT_FAILURE);

    ok = false;
    for (p1data_t *p = p1data_head->next; p != NULL; p = p->next) {
        if (!strcasecmp(p->schema_id, schema_name)) {
            ok = true;
            for (int i = 0; i < p->rule_count; i++)
                fprintf(stdout, "%s\n", p->rule_id_list[i]);         
        }        
    }

    if (!ok) {
        fprintf(stderr, "invalid schema: %s\n", schema_name);
        exit(EXIT_FAILURE);
    }
    exit(EXIT_SUCCESS);
}


int process_entities(char *exp_path, char *schema_name, int flags) {
    p1data_t pd, *p1data_head = &pd;
    FILE *f;
    yyscan_t lexer;
    int rc;
    bool ok;
    
    memset(p1data_head, 0, sizeof(p1data_t));
    p1data_head->exp_path = exp_path;
#ifdef EXP2CXX_CMAKE_HELPER
    p1data_head->exp2cxx_cmake_helper = flags & (CMAKE_HELPER_HEADERS | CMAKE_HELPER_IMPLS);
#endif

    p1lex_init(&lexer);
    f = fopen(exp_path, "r");
    p1set_in(f, lexer);
    rc = p1parse(p1data_head, lexer);
    if (rc)
        exit(EXIT_FAILURE);
    
    ok = false;
    for (p1data_t *p = p1data_head->next; p != NULL; p = p->next) {
        if (!strcasecmp(p->schema_id, schema_name)) {
            ok = true;
#ifdef EXP2CXX_CMAKE_HELPER
            if (flags & CMAKE_HELPER_HEADERS) {
                for (int i = 0; i < p->entity_count; i++)
                    fprintf(stdout, FMT_TYPE_H " ", p->entity_id_list[i]);
                fprintf(stdout, "\n");
            } else if (flags & CMAKE_HELPER_IMPLS) {
                for (int i = 0; i < p->entity_count; i++)
                    fprintf(stdout, FMT_TYPE_CC " ", p->entity_id_list[i]);
                fprintf(stdout, "\n");
            } else {
#endif
                for (int i = 0; i < p->entity_count; i++)
                    fprintf(stdout, "%s\n", p->entity_id_list[i]);
#ifdef EXP2CXX_CMAKE_HELPER
            }
#endif
        }
    }
    
    if (!ok) {
        fprintf(stderr, "invalid schema: %s\n", schema_name);
        exit(EXIT_FAILURE);
    }
    exit(EXIT_SUCCESS);
}

int process_types(char *exp_path, char *schema_name, int flags) {
    p1data_t pd, *p1data_head = &pd;
    FILE *f;
    yyscan_t lexer;
    int rc;
    bool ok;

    memset(p1data_head, 0, sizeof(p1data_t));
    p1data_head->exp_path = exp_path;
#ifdef EXP2CXX_CMAKE_HELPER
    p1data_head->exp2cxx_cmake_helper = flags & (CMAKE_HELPER_HEADERS | CMAKE_HELPER_IMPLS);
#endif
    
    p1lex_init(&lexer);
    f = fopen(exp_path, "r");
    p1set_in(f, lexer);
    rc = p1parse(p1data_head, lexer);
    if (rc)
        exit(EXIT_FAILURE);
    
    ok = false;
    for (p1data_t *p = p1data_head->next; p != NULL; p = p->next) {
        if (!strcasecmp(p->schema_id, schema_name)) {
            ok = true;
#ifdef EXP2CXX_CMAKE_HELPER
            /* TODO: this needs the pass 2 parser, in order to resolve base types */
            if (flags & CMAKE_HELPER_HEADERS) {
                for (int i = 0; i < p->type_count; i++)
                    fprintf(stdout, FMT_ENTITY_H " ", p->type_id_list[i]);
                fprintf(stdout, "\n");
            } else if (flags & CMAKE_HELPER_IMPLS) {
                for (int i = 0; i < p->type_count; i++)
                    fprintf(stdout, FMT_ENTITY_CC " ", p->type_id_list[i]);
                fprintf(stdout, "\n");
            } else {
#endif
                for (int i = 0; i < p->type_count; i++)
                    fprintf(stdout, "%s\n", p->type_id_list[i]);
#ifdef EXP2CXX_CMAKE_HELPER
            }
#endif
        }
    }
    
    
    if (!ok) {
        fprintf(stderr, "invalid schema: %s\n", schema_name);
        exit(EXIT_FAILURE);
    }
    exit(EXIT_SUCCESS);
}

int main(int argc, const char ** argv) {
    char *schema_name = NULL;
    int flags, i;
    char *cmd, *exp_path, *fmt;
    
    struct argparse argparse;
    /* TODO: yy_flex_debug, how set for reentrant lexer... using command option? */
    
    struct argparse_option options[] = {
        OPT_HELP(),
        OPT_STRING('s', "schema", &schema_name, "schema to query"),
        OPT_BOOLEAN('d', "debug", &p1debug, "debug the parser"),
#ifdef EXP2CXX_CMAKE_HELPER
        OPT_GROUP("exp2cxx cmake helpers"),
        OPT_BIT('i', "impls", &flags, "output .cc names", NULL, CMAKE_HELPER_IMPLS),
        OPT_BIT('x', "headers", &flags, "output .h names", NULL, CMAKE_HELPER_HEADERS),
#endif
        OPT_END(),
    };

    argparse_init(&argparse, options, usages, 0);
    argc = argparse_parse(&argparse, argc, argv);
    
    if (argc != 2) {
        argparse_usage(&argparse);
        exit(EXIT_FAILURE);
    }
#ifdef EXP2CXX_CMAKE_HELPER
    else if ((flags & CMAKE_HELPER_HEADERS) && (flags & CMAKE_HELPER_IMPLS)) {
        argparse_usage(&argparse);
        fprintf(stderr, "NOTE: --impl / --headers are mutually exclusive options\n");
        exit(EXIT_FAILURE);
    }
#endif
    
    cmd = (char *) argv[0];
    exp_path = (char *) argv[1];
    
    if (!strcmp("schemas", cmd)) {
        return process_schemas(exp_path);
    } else if (!strcmp("entities", cmd)) {
        return process_entities(exp_path, schema_name, flags);
    } else if (!strcmp("types", cmd)) {
        return process_types(exp_path, schema_name, flags);
    } else if (!strcmp("functions", cmd)) {
        return process_functions(exp_path, schema_name);
    } else if (!strcmp("procedures", cmd)) {
        return process_procedures(exp_path, schema_name);        
    } else if (!strcmp("rules", cmd)) {
        return process_rules(exp_path, schema_name);        
    } else {
        argparse_usage(&argparse);
        exit(EXIT_FAILURE);
    }
    
}
