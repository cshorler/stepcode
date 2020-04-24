#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <assert.h>

#define YYCTYPE unsigned char
#define YYCURSOR in->cur
#define YYLIMIT in->lim
#define YYMARKER in->mrk
#define YYCTXMARKER in->ctxmrk
#define YYFILL(n) do { \
        if (fill(in, n) != 0) { \
            fprintf(stderr, "lexer fill(...) failed, exiting\n"); \
            exit(1); \
        } \
    } while (0)

/*!max:re2c*/
#define BUFSZ 16384

/* reserved '(' ')' ';' '='
 */
#define T_P21_START     'S'
#define T_P21_END       'X'
#define T_HEADER        'H'
#define T_DATA          'D'
#define T_ENDSEC        'E'
#define T_EID           'I'
#define T_KEYWORD       'K'
#define T_VARIANT       'V'
#define T_EOF           '\x00'
#define T_ERROR         '\x01'



int debug = 1;
#define dprintf(fmt, ...) \
    do { if (debug) fprintf(stderr, "%s:%3d " fmt, __FILE__, __LINE__, ##__VA_ARGS__); } while (0)


/*!rules:re2c
 ascii_encoding = [][!"*$%&.#+,\-()?/:;<=>@{}|^`~0-9a-zA-Z_ ] | "''" | "\\\\" ;
 page_encoding  = "\\" [A-I] "\\" | "\\S\\" [][!"'*$%&.#+,\-()?/:;<=>@{}|^`~0-9a-zA-Z_\\ ] ;
 hex_encoding   = "\\X2\\" ([0-9A-F]{4})+ "\\X0\\" | "\\X4\\" ([0-9A-F]{8})+ "\\X0\\" ;
 byte_encoding  = "\\X\\" [0-9A-F]{2} ;

 NL = ("\n" | "\r\n") ;
 PUNCTUATION = [ ;()/] ;
 
 P21_START = "ISO-10303-21;" ;
 P21_END = "END-ISO-10303-21;" ;
 DATA = "DATA" ;
 HEADER = "HEADER;" ;
 ENDSEC = "ENDSEC;" ;

 WS = " " ;
 KEYWORD = "!"? [A-Za-z_] [0-9A-Za-z_]* ;
 REAL = [+-]* [0-9] [0-9]* "." [0-9]* ("E" [+-]* [0-9] [0-9]*)? ;
 INTEGER = [+-]* [0-9] [0-9]* ;
 STRING = "'" (ascii_encoding | page_encoding | hex_encoding | byte_encoding )* "'" ;
 BINARY = '"' [0-3] [0-9A-F]* '"' ;
 ENUMERATION = "." [A-Z_] [A-Z0-9_]* "." ;
 EID = "#" [0-9]+ ;

 <!*> { n = in->cur - in->sp; }
 WS+ { continue; }
 NL { in->lineno++; continue; }
 "/*" { lex_comment(in); continue; }
 * { YYCURSOR--; break; }

 */

typedef enum {
    V_REAL = 1,
    V_INTEGER,
    V_STRING,
    V_BINARY,
    V_ENUM,
    V_EID,
    V_DERIVED,
    V_EMPTY
} VariantType;

/* lexeme */
typedef struct {
    uint8_t token;
    uint8_t vtype;
    uint32_t lineno;
    size_t n;
    unsigned char *data;
} Symbol;

enum {
    P_FILE,
    P_HEADERSECTION,
    P_DATASECTION,
    P_HEADERENTITY,
    P_SIMPLEENTITY,
    P_COMPLEXENTITY,
    P_LIST,
    P_PARAMETER
};

typedef struct {
} File;

typedef struct {
} HeaderSection;

typedef struct {
} DataSection;

typedef struct {
} HeaderEntity;

typedef struct {
} SimpleEntity;

typedef struct {
} ComplexEntity;

typedef struct {
} List;

typedef struct {
} Parameter;

/* grammar reduction */
typedef struct {
    uint8_t type;
    union {
        File *file;
        HeaderSection *header_section;
        DataSection *data_section;
        HeaderEntity *header_entity;
        SimpleEntity *simple_entity;
        ComplexEntity *complex_entity;
        List *list;
        Parameter *parameter;
    };
} Production;

enum {
    I_SYMBOL,
    I_PRODUCTION
};

typedef struct {
    uint8_t type;
    union {
        Symbol sym;
        struct { uint8_t token; };
        Production prod;
    };
} Item;

typedef struct {
    FILE *file;
    unsigned char *cur, *mrk, *ctxmrk, *lim;
    unsigned char *sp, *basemrk;
    int eof;
    uint32_t lineno;    
    /* 3 lookahead +1 (for error token) */
    int nsym;
    Symbol sym[4];
    unsigned char buf[BUFSZ+YYMAXFILL];
} Input;

typedef struct {
    int idx_top;
    int idx_lim;
    Item *items;
} Stack;

/* LL(3) parser */
typedef struct {
    Input *in;
    Stack *stack;
} Parser;


void recover(Input *in, uint32_t followset);
void p21_exchange_file(Parser *);
void p21_complex_entity_instance(Parser *);
void p21_data_section(Parser *);
void p21_data_section_list(Parser *);
void p21_entity_instance(Parser *);
void p21_entity_instance_list(Parser *);
void p21_header_entity(Parser *);
void p21_header_entity_list(Parser *);
void p21_header_section(Parser *);
void p21_parameter(Parser *);
void p21_parameter_list(Parser *);
void p21_simple_entity_instance(Parser *);
void p21_simple_record(Parser *);
void p21_simple_record_list(Parser *);
Symbol lpop(Input *, uint8_t );

#define PUSH_TERMINAL(stack, sym) do { \
        Item it = (Item){I_SYMBOL, (sym)}; \
        if (it.token == T_ERROR) goto err; \
        push((stack), it); \
    } while (0)

void push(Stack *stack, Item it) {
    if (stack->idx_top == stack->idx_lim) {
        Item *nitems = realloc(stack->items, 2 * stack->idx_lim * sizeof stack->items[0]);
        if (!nitems) {
            fprintf(stderr, "failed to grow parser stack, memory exhausted\n");
            exit(1);
        }
        stack->items = nitems;
        stack->idx_lim *= 2;
    }
    
    stack->items[stack->idx_top++] = it;
}

/* mock implementations */
void drop(Stack *stack, uint32_t n) {
    assert(stack->idx_top >= n);
    stack->idx_top -= n;
}

void unwind(Stack *stack, int bsp) {
    stack->idx_top = bsp;
}

Item pop(Stack *stack) {
    assert(stack->idx_top >= 1);
}

Symbol lpop(Input *in, uint8_t token) {
    Symbol *stack = in->sym;
    Symbol sym = stack[0];
    
    /* missing input or unexpected lookahead token */
    if (in->nsym == 0 || stack[0].token != token)
        return (Symbol){T_ERROR};
    
    if (!--in->nsym) {
        memset(&in->sym[0], 0, sizeof in->sym[0]);
    } else {
        memmove(&in->sym[0], &in->sym[1], in->nsym * sizeof in->sym[0]);
        memset(&in->sym[in->nsym], 0, sizeof in->sym[0]);
    }
    
    return sym;
}

static int fill(Input *in, size_t need)
{
    size_t free;
    if (in->eof) {
        return 1;
    }
    free = in->basemrk - in->buf;
    if (free < need) {
        return 2;
    }
    memmove(in->buf, in->basemrk, in->lim - in->basemrk);
    in->lim -= free;
    in->cur -= free;
    in->mrk -= free;
    in->ctxmrk -= free;
    in->basemrk -= free;
    in->sp -= free;
    in->lim += fread(in->lim, 1, free, in->file);
    if (in->lim < in->buf + BUFSZ) {
        in->eof = 1;
        memset(in->lim, 0, YYMAXFILL);
        in->lim += YYMAXFILL;
    }
    return 0;
}

static void init(Parser *p, FILE *file)
{
    Stack *stack;
    Input *in; 

    in = malloc(sizeof *in);
    if (!in)
        goto err;
    memset(in, 0, sizeof *in);
    in->file = file;
    in->cur = in->basemrk = in->sp = in->lim = in->buf + BUFSZ;
    in->lineno = 1;
    fill(in, 1);

    stack = malloc(sizeof *stack);
    if (!stack)
        goto err;
    memset(stack, 0, sizeof *stack);
    stack->idx_lim = 16;
    stack->idx_top = 0;
    stack->items = malloc(stack->idx_lim * sizeof stack->items[0]);
    if (!stack->items)
        goto err;

    p->in = in;
    p->stack = stack;
    
    return;
    
err:
    fprintf(stderr, "failed to initialise parse stack\n");
    exit(1);
}




/* myfu compile time checks */
#define lshift(u, n) ((u) & ~0xff ? ((uint32_t) 0UL) & (u) << 24 : (uint32_t)(u) << (n))
#define pack(u0, u1, u2, u3) (((u0) << 24) | ((u1) << 16) | ((u2) << 8) | ((u3) << 0))

/* bitfu http://graphics.stanford.edu/~seander/bithacks.html */
#define haszero(v) (((v) - 0x01010101UL) & ~(v) & 0x80808080UL)
#define hasvalue(x,n) (haszero((x) ^ (~0UL/255 * (n))))

/* ppfu https://stackoverflow.com/a/11763277/1162349 */
#define GET_MACRO(_1, _2, _3, _4, NAME, ...) NAME

#define PUSH_SYMBOL(...) GET_MACRO(__VA_ARGS__, _4, _3, _PUSH_SYMBOL2, _PUSH_SYMBOL1)(__VA_ARGS__)
#define _PUSH_SYMBOL1(token) in->sym[in->nsym++] = (Symbol){(token), 0, in->lineno, n, in->sp}
#define _PUSH_SYMBOL2(token, vtype) in->sym[in->nsym++] = (Symbol){(token), (vtype), in->lineno, n, in->sp}

#define PUSH_ERROR() do { \
        assert(in->nsym < 4); \
        in->nsym++; \
        memmove(&in->sym[1], &in->sym[0], 3 * sizeof in->sym[0]); \
        in->sym[0] = (Symbol){T_ERROR}; \
    } while (0)


/* test for one in a set of 1 to 4 e.g. {t0, t1, t2, t3} */
#define LOOKAHEAD(x, ...) GET_MACRO(__VA_ARGS__, _LOOKAHEAD4, _LOOKAHEAD3, _LOOKAHEAD2, _LOOKAHEAD1)(x, __VA_ARGS__)
#define _LOOKAHEAD1(x, t0)             ((t0) == (x.token))
#define _LOOKAHEAD2(x, t0, t1)         ((t0) == (x.token) || (t1) == (x.token))
#define _LOOKAHEAD3(x, t0, t1, t2)     hasvalue(pack((t0),(t1),(t2),0U),(x.token))
#define _LOOKAHEAD4(x, t0, t1, t2, t3) hasvalue(pack((t0),(t1),(t2),(t3)),(x.token))


void lex_comment(Input *in) {
    size_t n;
    int comment_lvl = 1;
    
    while (1) {
        in->sp = in->cur;
        /*!use:re2c
        NOT_SLASH_STAR = [][!"#$%&'()+,\-.:;<=>?@\\^`{|}~0-9A-Z_a-z ] ;     

        "*"+ "/" {
            if (!--comment_lvl) { break; }
            else { continue; }
        }
        "*"+ { continue; }
        NOT_SLASH_STAR+ { continue; }
        "/" { continue; }
        "/*" { ++comment_lvl; continue; } */
    }
    
    return;
    
err:
    fprintf(stderr, "invalid character in comment, exiting\n");
    exit(1);
}

#define recover(in, ...) GET_MACRO(__VA_ARGS__, _4, _RECOVER3, _RECOVER2, _RECOVER1)(in, __VA_ARGS__)
#define _RECOVER1(in, u0) _recover((in), (u0), 0U, 0U)
#define _RECOVER2(in, u0, u1) _recover((in), (u0), (u1), 0U)
#define _RECOVER3(in, u0, u1, u2) _recover((in), (u0), (u1), (u2))

void _recover(Input *in, uint8_t u0, uint8_t u1, uint8_t u2) {
    size_t n;
    Symbol sym;
    
    while (in->nsym) {
        if (LOOKAHEAD(in->sym[0], u0, u1, u2, T_EOF))
            break;
        --in->nsym;
        memmove(&in->sym[0], &in->sym[1], in->nsym * sizeof in->sym[0]);
        memset(&in->sym[in->nsym], 0, sizeof in->sym[0]);
    }
    
    if (in->nsym)
        return;
    
    while (1) {
        in->sp = in->cur;
        /*!use:re2c
         P21_START      { sym = (Symbol){T_P21_START}; goto check; }
         P21_END        { sym = (Symbol){T_P21_END}; goto check; }
         HEADER         { sym = (Symbol){T_HEADER}; goto check; }
         DATA / PUNCTUATION { sym = (Symbol){T_DATA}; goto check; }
         ENDSEC         { sym = (Symbol){T_ENDSEC}; goto check; }
         EID            { sym = (Symbol){T_EID}; goto check; }
         KEYWORD        { sym = (Symbol){T_KEYWORD}; goto check; }
         REAL           { sym = (Symbol){T_VARIANT, V_REAL}; goto check; }
         INTEGER        { sym = (Symbol){T_VARIANT, V_INTEGER}; goto check; }
         STRING         { sym = (Symbol){T_VARIANT, V_STRING}; goto check; }
         BINARY         { sym = (Symbol){T_VARIANT, V_BINARY}; goto check; }
         ENUMERATION    { sym = (Symbol){T_VARIANT, V_ENUM}; goto check; }
         "*"            { sym = (Symbol){T_VARIANT, V_DERIVED}; goto check; }
         "$"            { sym = (Symbol){T_VARIANT, V_EMPTY}; goto check; }
         [();]          { sym = (Symbol){*in->sp}; goto check; }
        */
check:
        if (LOOKAHEAD(sym, u0, u1, u2, T_EOF)) {
            PUSH_SYMBOL(sym.token, sym.vtype);
            break;
        }
    }
    
    return;
    
err:
    fprintf(stderr, "fatal, failed to resolve follow set (%c, %c, %c)\n", u0, u1, u2);
    exit(1);
}


/*
 * Parser
 */
void p21_exchange_file(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    Input *in = p->in;
    
    while (in->nsym < 1) {
        in->sp = in->cur;
        /*!use:re2c
        P21_START { PUSH_SYMBOL(T_P21_START); continue;} */
    }
    PUSH_TERMINAL(p->stack, lpop(in, T_P21_START));

    p21_header_section(p);
    p21_data_section_list(p);

    PUSH_TERMINAL(p->stack, lpop(in, T_P21_END));
    
    assert(p->stack->idx_top == 4);
    drop(p->stack, 4);
    push(p->stack, (Item){I_PRODUCTION, {P_FILE, 0}});
    
    return;

err:
    fprintf(stderr, "syntax error #2, resyncing\n");
    recover(in, T_EOF);
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_header_section(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    uint32_t len = 5;
    Input *in = p->in;
    
    while (in->nsym < 1) {
        in->sp = in->cur;
        /*!use:re2c re2c:labelprefix = 'yya';
        HEADER { PUSH_SYMBOL(T_HEADER); continue; } */
    }
    PUSH_TERMINAL(p->stack, lpop(in, T_HEADER));
    
    /* mandatory headers */
    p21_header_entity(p);
    p21_header_entity(p);
    p21_header_entity(p);
   
    while (in->nsym < 1) {
        in->sp = in->cur;
        /*!use:re2c re2c:labelprefix = 'yyb';
         ENDSEC { PUSH_SYMBOL(T_ENDSEC); continue; }
         KEYWORD { PUSH_SYMBOL(T_KEYWORD); continue; } */
    }
    
    /* optional headers */
    if (LOOKAHEAD(in->sym[0], T_KEYWORD)) {
        p21_header_entity_list(p);
        len++;
    }

    PUSH_TERMINAL(p->stack, lpop(in, T_ENDSEC));

    /* reduction */
    drop(p->stack, len);
    push(p->stack, (Item){I_PRODUCTION, {P_HEADERSECTION, 0}});
    
    return;
    
err:
    fprintf(stderr, "syntax error #3, resyncing\n");
    recover(in, T_DATA);
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_data_section_list(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    uint32_t len = 0;
    Input *in = p->in;

    do {
        while (in->nsym < 1) {
            in->sp = in->cur;
            /*!use:re2c
             DATA / PUNCTUATION { PUSH_SYMBOL(T_DATA); continue; }
             P21_END { PUSH_SYMBOL(T_P21_END); continue; } */
        }
        if (!LOOKAHEAD(in->sym[0], T_DATA))
            break;
        p21_data_section(p);
    } while (++len);

    // one or more
    if (!len) {
        PUSH_ERROR();
        goto err;
    }
    
    /* reduction */
    drop(p->stack, len);
    push(p->stack, (Item){I_PRODUCTION, {P_LIST, 0}});
    
    return;
    
err:
    fprintf(stderr, "syntax error #4, resyncing\n");
    recover(in, T_P21_END);
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_data_section(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    uint32_t len = 3;
    Input *in = p->in;

    while (in->nsym < 2) {
        in->sp = in->cur;
        /*!use:re2c re2c:labelprefix = 'yya';
         [(;] { PUSH_SYMBOL(*in->sp); continue; } */
    }
    PUSH_TERMINAL(p->stack, lpop(in, T_DATA));
    
    if (LOOKAHEAD(in->sym[0], '(')) {
        PUSH_TERMINAL(p->stack, lpop(in, '('));
        
        p21_parameter_list(p);
        while (in->nsym < 2) {
            in->sp = in->cur;
            /*!use:re2c re2c:labelprefix = 'yyb';
            ";" { PUSH_SYMBOL(';'); continue; } */
        }
        
        PUSH_TERMINAL(p->stack, lpop(in, ')'));
        len += 3;
    }
    PUSH_TERMINAL(p->stack, lpop(in, ';'));

    while (in->nsym < 1) {
        in->sp = in->cur;
        /*!use:re2c re2c:labelprefix = 'yyc';
        ENDSEC { PUSH_SYMBOL(T_ENDSEC); continue; }
        EID { PUSH_SYMBOL(T_EID); continue; } */
    }
    if (LOOKAHEAD(in->sym[0], T_EID)) {
        p21_entity_instance_list(p);
        len++;
    }
    
    PUSH_TERMINAL(p->stack, lpop(in, T_ENDSEC));

    /* reduction */
    drop(p->stack, len);
    push(p->stack, (Item){I_PRODUCTION, {P_DATASECTION, 0}});
    
    return;

err:
    fprintf(stderr, "syntax error #5, resyncing\n");
    recover(in, T_P21_END, T_DATA);
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_header_entity(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    Input *in = p->in;
    
    /* set KEYWORD as basemrk to prevent fill() recycling the buffer before user action */
    while (in->nsym < 1) {
        in->sp = in->cur;
        /*!use:re2c
         KEYWORD { PUSH_SYMBOL(T_KEYWORD); continue; } */
    }
    in->basemrk = in->sym[0].data;

    p21_simple_record(p);
    
    while (in->nsym < 1) {
        in->sp = in->cur;
        /*!use:re2c
         ";" { PUSH_SYMBOL(';'); continue; } */
    }
    PUSH_TERMINAL(p->stack, lpop(in, ';'));

    /* reduction */
    drop(p->stack, 2);
    push(p->stack, (Item){I_PRODUCTION, {P_HEADERENTITY, 0}});
    
    return;
    
err:
    fprintf(stderr, "syntax error #6, resyncing\n");
    recover(in, T_ENDSEC, T_KEYWORD);
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_header_entity_list(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    uint32_t len = 1;
    Input *in = p->in;

    p21_header_entity(p);
    
    do {
        while (in->nsym < 1) {
            in->sp = in->cur;
            /*!use:re2c
             KEYWORD { PUSH_SYMBOL(T_KEYWORD); continue; }
             ENDSEC { PUSH_SYMBOL(T_ENDSEC); continue; } */
        }
        if (!LOOKAHEAD(in->sym[0], T_KEYWORD))
            break;
        p21_header_entity(p);
    } while (++len);
        
    /* reduction */
    drop(p->stack, len);
    push(p->stack, (Item){I_PRODUCTION, {P_LIST, 0}});
    
    return;
    
err:
    fprintf(stderr, "syntax error #7, resyncing\n");
    recover(in, T_ENDSEC);
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_entity_instance_list(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    uint32_t len = 1;
    Input *in = p->in;

    p21_entity_instance(p);
    
    do {
        while (in->nsym < 1) {
            in->sp = in->cur;
            /*!use:re2c
             EID { PUSH_SYMBOL(T_EID); continue; }
             ENDSEC { PUSH_SYMBOL(T_ENDSEC); continue; } */
        }
        if (!LOOKAHEAD(in->sym[0], T_EID))
            break;
        p21_entity_instance(p);
    } while (++len);
    
    drop(p->stack, len);
    push(p->stack, (Item){I_PRODUCTION, {P_LIST, 0}});
    
    return;
    
err:
    fprintf(stderr, "syntax error #8, resyncing\n");
    recover(in, T_ENDSEC);
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_parameter_list(Parser *p) {    
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    uint32_t len = 1;
    Input *in = p->in;

    p21_parameter(p);

    do {
        while (in->nsym < 1) {
            in->sp = in->cur;
            /*!use:re2c
             [,)] { PUSH_SYMBOL(*in->sp); continue; } */
        }
        if (LOOKAHEAD(in->sym[0], ')'))
            break;

        PUSH_TERMINAL(p->stack, lpop(in, ','));
        p21_parameter(p);
    } while (len += 2);

    /* reduction */
    drop(p->stack, len);
    push(p->stack, (Item){I_PRODUCTION, {P_LIST, 0}});
    
    return;
    
err:
    fprintf(stderr, "syntax error #9, resyncing\n");
    recover(in, ')', ';');
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_entity_instance(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    Input *in = p->in;

    while (in->nsym < 3) {
        in->sp = in->cur;
        /*!use:re2c
         KEYWORD { PUSH_SYMBOL(T_KEYWORD); continue; }
         [(=] { PUSH_SYMBOL(*in->sp); continue; } */
    }
    if (!LOOKAHEAD(in->sym[0], T_EID) || !LOOKAHEAD(in->sym[1], '=')) {
        PUSH_ERROR();
        goto err;
    }
    
    /* set EID as basemrk to prevent fill() recycling the buffer before user action */
    in->basemrk = in->sym[0].data;
    
    if (LOOKAHEAD(in->sym[2], T_KEYWORD)) {
        p21_simple_entity_instance(p);
    } else if (LOOKAHEAD(in->sym[2], '(')) {
        p21_complex_entity_instance(p);
    }

    /* TODO: reduction */
    drop(p->stack, 1);
    push(p->stack, (Item){I_PRODUCTION, 0});
    
    return;
    
err:
    fprintf(stderr, "syntax error #10, resyncing\n");
    recover(in, T_ENDSEC, T_EID);
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_simple_entity_instance(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    Input *in = p->in;

    PUSH_TERMINAL(p->stack, lpop(in, T_EID));
    PUSH_TERMINAL(p->stack, lpop(in, '='));
    
    p21_simple_record(p);

    while (in->nsym < 1) {
        in->sp = in->cur;
        /*!use:re2c
         ";" { PUSH_SYMBOL(';'); continue; } */
    }
    PUSH_TERMINAL(p->stack, lpop(in, ';'));

    /* reduction */
    drop(p->stack, 4);
    push(p->stack, (Item){I_PRODUCTION, {P_SIMPLEENTITY, 0}});
    
    return;
    
err:
    fprintf(stderr, "syntax error #12, resyncing\n");
    recover(in, T_ENDSEC, T_EID);
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_complex_entity_instance(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    Input *in = p->in;

    PUSH_TERMINAL(p->stack, lpop(in, T_EID));
    PUSH_TERMINAL(p->stack, lpop(in, '='));
    PUSH_TERMINAL(p->stack, lpop(in, '('));
    
    p21_simple_record_list(p);

    while (in->nsym < 2) {
        in->sp = in->cur;
        /*!use:re2c
         ";" { PUSH_SYMBOL(';'); continue; } */
    }
    
    PUSH_TERMINAL(p->stack, lpop(in, ')'));
    PUSH_TERMINAL(p->stack, lpop(in, ';'));

    /* reduction */
    drop(p->stack, 6);
    push(p->stack, (Item){I_PRODUCTION, {P_COMPLEXENTITY, 0}});
    
    return;
    
err:
    fprintf(stderr, "syntax error #13, resyncing\n");
    recover(in, T_ENDSEC, T_EID);
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_simple_record(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    uint32_t len = 3;
    Input *in = p->in;

    while (in->nsym < 3) {
        in->sp = in->cur;
        /*!use:re2c
         KEYWORD { PUSH_SYMBOL(T_KEYWORD); continue; }
         REAL { PUSH_SYMBOL(T_VARIANT, V_REAL); continue; }
         INTEGER { PUSH_SYMBOL(T_VARIANT, V_INTEGER); continue; }
         STRING { PUSH_SYMBOL(T_VARIANT, V_STRING); continue; }
         BINARY { PUSH_SYMBOL(T_VARIANT, V_BINARY); continue; }
         ENUMERATION { PUSH_SYMBOL(T_VARIANT, V_ENUM); continue; }
         EID { PUSH_SYMBOL(T_VARIANT, V_EID); continue; }
         "*" { PUSH_SYMBOL(T_VARIANT, V_DERIVED); continue; }
         "$" { PUSH_SYMBOL(T_VARIANT, V_EMPTY); continue; }
         [()] { PUSH_SYMBOL(*in->sp); continue; } */
    }

    PUSH_TERMINAL(p->stack, lpop(in, T_KEYWORD));
    PUSH_TERMINAL(p->stack, lpop(in, '('));
    
    if (LOOKAHEAD(in->sym[0], '(', T_KEYWORD, T_VARIANT)) {
        p21_parameter_list(p);
        len++;
    }

    PUSH_TERMINAL(p->stack, lpop(in, ')'));

    /* TODO: reduction */
    drop(p->stack, len);
    push(p->stack, (Item){I_PRODUCTION, {0}});
    
    return;
    
err:
    fprintf(stderr, "syntax error #14, resyncing\n");
    recover(in, ';', ')', T_KEYWORD);
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_simple_record_list(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    uint32_t len = 1;
    Input *in = p->in;

    p21_simple_record(p);
    
    do {
        while (in->nsym < 1) {
            in->sp = in->cur;
            /*!use:re2c
             KEYWORD { PUSH_SYMBOL(T_KEYWORD); continue; }
             ")" { PUSH_SYMBOL(')'); continue; } */
        }
        if (!LOOKAHEAD(in->sym[0], T_KEYWORD))
            break;
        p21_simple_record(p);
    } while (++len);

    /* reduction */
    drop(p->stack, len);
    push(p->stack, (Item){I_PRODUCTION, {P_LIST, 0}});
    
    return;
    
err:
    fprintf(stderr, "syntax error #15, resyncing\n");
    recover(in, ')', ';');
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}

void p21_parameter(Parser *p) {
    size_t n;
    uint32_t bsp = p->stack->idx_top;
    uint32_t len = 1;
    Input *in = p->in;

    while (in->nsym < 2) {
        in->sp = in->cur;
        /*!use:re2c re2c:labelprefix='yya';
         KEYWORD { PUSH_SYMBOL(T_KEYWORD); continue; }
         REAL { PUSH_SYMBOL(T_VARIANT, V_REAL); continue; }
         INTEGER { PUSH_SYMBOL(T_VARIANT, V_INTEGER); continue; }
         STRING { PUSH_SYMBOL(T_VARIANT, V_STRING); continue; }
         BINARY { PUSH_SYMBOL(T_VARIANT, V_BINARY); continue; }
         ENUMERATION { PUSH_SYMBOL(T_VARIANT, V_ENUM); continue; }
         EID { PUSH_SYMBOL(T_VARIANT, V_EID); continue; }
         "*" { PUSH_SYMBOL(T_VARIANT, V_DERIVED); continue; }
         "$" { PUSH_SYMBOL(T_VARIANT, V_EMPTY); continue; }
         [(),] { PUSH_SYMBOL(*in->sp); continue; } */
    }
    
    if (LOOKAHEAD(in->sym[0], T_VARIANT)) {
        PUSH_TERMINAL(p->stack, lpop(in, T_VARIANT));
    } else {
        if (LOOKAHEAD(in->sym[0], T_KEYWORD)) {
            PUSH_TERMINAL(p->stack, lpop(in, T_KEYWORD));
            PUSH_TERMINAL(p->stack, lpop(in, '('));
            p21_parameter(p);
            len += 2;
        } else {
            PUSH_TERMINAL(p->stack, lpop(in, '('));
            if (LOOKAHEAD(in->sym[0], '(', T_KEYWORD, T_VARIANT)) {
                p21_parameter_list(p);
                len++;
            }
        }
        while (in->nsym < 1) {
            in->sp = in->cur;
            /*!use:re2c re2c:labelprefix='yyb';
             ")" { PUSH_SYMBOL(')'); continue; } */
        }
        PUSH_TERMINAL(p->stack, lpop(in, ')'));
        len++;
    }
    
    /* reduction */
    drop(p->stack, len);
    push(p->stack, (Item){I_PRODUCTION, {P_PARAMETER, 0}});
    
    return;

err:
    fprintf(stderr, "syntax error #16, resyncing\n");
    recover(in, ')', ',', ';');
    unwind(p->stack, bsp);
    push(p->stack, (Item){I_SYMBOL, {T_ERROR}});
}




int main(char *argv[], int argc) {
    const char *paths[] = {
        "/home/chorler/projects/src/stepcode/test/p21/test_array_bounds_FAIL1.p21",
        "/home/chorler/projects/src/stepcode/test/p21/comments.p21",
        "/home/chorler/projects/src/stepcode/test/p21/test_inverse_attr.p21",
        "/home/chorler/projects/src/stepcode/test/p21/missing_and_required.p21",
        "/home/chorler/projects/src/stepcode/test/p21/test_array_bounds.p21",
        "/home/chorler/projects/src/stepcode/test/p21/test_inherit_inverse.p21",
        "/home/chorler/projects/src/stepcode/data/ap214e3/as1-oc-214.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/dm1-id-214.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/MAINBODY.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/HEAD_BACK.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/HEAD_FRONT.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/TAIL.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/MAINBODY_FRONT.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/FOOT_BACK_000.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/FOOT_FRONT_000.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/s1-c5-214.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/MAINBODY_BACK.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/HEAD.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/TAIL_TURBINE.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/TAIL_MIDDLE_PART.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/s1-c5-214/FOOT.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/sg1-c5-214.stp",
        "/home/chorler/projects/src/stepcode/data/ap214e3/io1-cm-214.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS7-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS1Mod0-outresult.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS2-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS1Mod0-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS3-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS10Mod0-outresult.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS2Mod0-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS8-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS3Mod0-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS4Mod0-outresult.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS7Mod0-outresult.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS4Mod0-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS10Mod0-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS3Mod0-outresult.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS8Mod0-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS4-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS7Mod0-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS2Mod0-outresult.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS8Mod0-outresult.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS10-out.stp",
        "/home/chorler/projects/src/stepcode/data/ap209/ATS1-out.stp"
    };
    
    Parser myp;
    FILE *fp;
    
    for (unsigned int i = 0; i < (sizeof paths / sizeof paths[0]); i++) {
        fp = fopen(paths[i], "rb");
        if (!fp) { fprintf(stderr, "failed to read input: %s\n", paths[i]); continue; }
        else { fprintf(stderr, "processing: %s\n", paths[i]); }
        init(&myp, fp);
        p21_exchange_file(&myp);
    }    
}
